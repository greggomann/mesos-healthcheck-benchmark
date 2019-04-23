# Mesos Default Executor Command Health Checks benchmarks

## Dependencies
- [maws|https://github.com/mesosphere/maws] should be installed and is
  used to create temporary AWS credentials.
- [dcos-launch|https://github.com/dcos/dcos-launch] is used to create
  DC/OS EE clusters on AWS. It's bundled in this repository.
- The DC/OS CLI must be installed and is used to create a service
  account.
- A valid DC/OS license in `genconf/license.txt`.

## Usage
Use the `create-cluster.sh` script to create a DC/OS cluster and to run
the benchmark suite on it.

The script can be configured via the following environment variables:

Name             | Default value
---------------- | -------------
`INSTALLER_URL`  | https://s3.amazonaws.com/downloads.mesosphere.io/dcos-enterprise/testing/pull/5608/commit/99de8a3e4d08ee68301c1ddd6d943d9a2d33974e/dcos_generate_config.ee.sh
`AWS_KEY_NAME`   | `default`
`SSH_KEY`        | `${HOME}/.ssh/mesosphere_shared`
`INSTANCE_TYPE`  | `m4.xlarge`
`CHECK_INTERVAL` | `60` (seconds)
`CHECK_TIMEOUT`  | `30` (seconds)

**Note:** you can reuse a cluster by copying the an existing
`cluster_config.yaml` file to the `results-${INSTANCE_TYPE}` directory.
