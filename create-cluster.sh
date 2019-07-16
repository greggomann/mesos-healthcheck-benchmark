#!/usr/bin/env bash

eval $(maws login 273854932432_Mesosphere-PowerUser)

INSTALLER_URL=${INSTALLER_URL:-https://s3.amazonaws.com/downloads.mesosphere.io/dcos-enterprise/testing/master/commit/e17a56b4343a9b415785254f4beaadb9277fee05/dcos_generate_config.ee.sh}
AWS_KEY_NAME=${AWS_KEY_NAME:-default}
SSH_KEY=${SSH_KEY:-"${HOME}/.ssh/mesosphere_shared_aws.pem"}
INSTANCE_TYPE=${INSTANCE_TYPE:-m4.xlarge}
CHECK_INTERVAL=${CHECK_INTERVAL:-60}
CHECK_TIMEOUT=${CHECK_TIMEOUT:-30}
LEFT_LIMIT=0
RIGHT_LIMIT=400
BREAK_ON_FAILURE=0

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

run_command() {
  ssh -l centos -A -p 22 -oConnectTimeout=10 -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null -oLogLevel=QUIET -oBatchMode=yes -oPasswordAuthentication=no -i ${SSH_KEY} -t $@
}

copy_file() {
  scp -P 22 -oConnectTimeout=10 -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null -oLogLevel=ERROR -oBatchMode=yes -oPasswordAuthentication=no -i ${SSH_KEY} $@
}

message() {
  echo -e "${GREEN}$@${NC}"
}

error() {
  echo -e "${RED}$@${NC}"
  exit 1
}

RESULTS_DIR="results-${INSTANCE_TYPE}"

mkdir -p $RESULTS_DIR
if [ $? -ne 0 ]; then
  error "Can't create results dir, exiting..."
fi

CLUSTER_CONFIG="${RESULTS_DIR}/cluster_config.yaml"
if [ ! -f ${CLUSTER_CONFIG} ]; then
  cat <<-EOF >${CLUSTER_CONFIG}
		---
		launch_config_version: 1
		deployment_name: greg-dcos-113s-strict-$(echo ${INSTANCE_TYPE}|sed -e 's/\./-/g')-${RANDOM}
		installer_url: ${INSTALLER_URL}
		platform: aws
		provider: onprem
		aws_region: us-west-2
		aws_key_name: ${AWS_KEY_NAME}
		ssh_private_key_filename: ${SSH_KEY}
		instance_type: ${INSTANCE_TYPE}
		bootstrap_instance_type: m4.xlarge
		dcos_config:
		  cluster_name: Health check benchmarking cluster ${INSTANCE_TYPE}
		  resolvers:
		    - 8.8.4.4
		    - 8.8.8.8
		  dns_search: mesos
		  master_discovery: static
		  exhibitor_storage_backend: static
		  security: strict
		num_masters: 1
		num_private_agents: 1
		num_public_agents: 0
		ssh_user: centos
		genconf_dir: ${PWD}/genconf
	EOF
fi

cat ${CLUSTER_CONFIG}

message "Saving results in ${RESULTS_DIR}..."

CLUSTER_INFO_PATH=${CLUSTER_INFO_PATH:-${RESULTS_DIR}/cluster_info.$INSTANCE_TYPE.json}
INSTALLATION_PENDING="${RESULTS_DIR}/install-pending.${INSTANCE_TYPE}.tmp"

if [ ! -f ${CLUSTER_INFO_PATH} ]; then
  message "Creating cluster with agent instance type ${INSTANCE_TYPE}..."

  ./dcos-launch create -c ${CLUSTER_CONFIG} -i ${CLUSTER_INFO_PATH}

  if [ $? -ne 0 ]; then
    error "Can't create cluster, exiting..."
  fi

  touch "${INSTALLATION_PENDING}"
fi

if [ -f "${INSTALLATION_PENDING}" ]; then
  message "Installing DC/OS...${NC}"

  ./dcos-launch wait -i ${CLUSTER_INFO_PATH}

  if [ $? -ne 0 ]; then
    error "Can't install DC/OS, exiting..."
  fi

  rm "${INSTALLATION_PENDING}"
fi

message "Gathering cluster information...${NC}"

export AGENT_IP=$(./dcos-launch describe -L critical -i "${CLUSTER_INFO_PATH}" | jq -r ".private_agents[0].public_ip")
if [ $? -ne 0 ]; then
  error "Can't get the agent's IP, exiting..."
fi
message "Agent at: ${AGENT_IP}${NC}"

export MASTER_IP=$(./dcos-launch describe -L critical -i "${CLUSTER_INFO_PATH}" | jq -r ".masters[0].public_ip")
if [ $? -ne 0 ]; then
  error "Can't get the master's IP, exiting..."
fi
message "Master at: ${MASTER_IP}${NC}"


dcos cluster list | grep "${MASTER_IP}" &>/dev/null
if [ $? -ne 0 ]; then
  message "Setting up DC/OS CLI for ${MASTER_IP}...${NC}"
  dcos cluster setup --insecure --username=bootstrapuser --password=deleteme --no-check "https://${MASTER_IP}"
fi

SERVICE_ACCOUNT=mesos-execute

# Create service account
dcos security org service-accounts show ${SERVICE_ACCOUNT} &>/dev/null

if [ $? -ne 0 ]; then
  message "Creating service account...${NC}"

  dcos security org service-accounts create -p ${SERVICE_ACCOUNT}.pem.pub -d "${SERVICE_ACCOUNT} service account" ${SERVICE_ACCOUNT}

  # Store service account credentials in vault.
  dcos security secrets create-sa-secret --strict ${SERVICE_ACCOUNT}.pem ${SERVICE_ACCOUNT} "${SERVICE_ACCOUNT}-secret"

  # Give rights to register with role *.
  dcos security org users grant ${SERVICE_ACCOUNT} 'dcos:mesos:master:framework:role:*' create

  # Allow creating tasks as user nobody.
  dcos security org users grant ${SERVICE_ACCOUNT} dcos:mesos:master:task:user:nobody create
  dcos security org users grant ${SERVICE_ACCOUNT} dcos:mesos:master:task:user:root create
  dcos security org users grant ${SERVICE_ACCOUNT} dcos:superuser full
fi

message "Checking out benchmark suite on master..."
run_command ${MASTER_IP} "/opt/mesosphere/bin/dcos-shell rm -rf mesos-healthcheck-benchmark"
run_command ${MASTER_IP} "/opt/mesosphere/bin/dcos-shell git clone https://github.com/greggomann/mesos-healthcheck-benchmark"
run_command ${MASTER_IP} "cd mesos-healthcheck-benchmark && git checkout dev"

message "Running benchmark suite from master..."
run_command ${MASTER_IP} "cd mesos-healthcheck-benchmark && sudo -E /opt/mesosphere/bin/dcos-shell ./run-test-check-throughput.sh ${AGENT_IP} ${CHECK_INTERVAL} ${CHECK_TIMEOUT} ${LEFT_LIMIT} ${RIGHT_LIMIT} ${BREAK_ON_FAILURE}"

message "Downloading results from master..."
copy_file "centos@${MASTER_IP}:mesos-healthcheck-benchmark/results-*.tgz" "${RESULTS_DIR}/"
# run_command ${MASTER_IP} "rm -f mesos-healthcheck-benchmark/results-*.tgz"
