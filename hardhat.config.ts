import '@nomiclabs/hardhat-ethers';
import '@nomiclabs/hardhat-etherscan';
import 'hardhat-gas-reporter';
import 'solidity-coverage';
import 'hardhat-deploy';

import { NetworkDefinition, EtherscanConfig } from './local.config';

export default {
  default: 'hardhat',
  networks: {
    localhost: {
      saveDeployments: true,
    },
    hardhat: {
      saveDeployments: true,
    },
    ...NetworkDefinition,
  },
  solidity: {
    version: '0.7.6',
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  namedAccounts: {
    deployer: 0,
  },
  paths: {
    sources: './contracts',
    tests: './test',
    cache: './build/cache',
    artifacts: './build/artifacts',
    deploy: 'deploy',
    deployments: 'deployments',
  },
  gasReporter: {
    currency: 'USD',
    enabled: true,
  },
  etherscan: EtherscanConfig,
};
