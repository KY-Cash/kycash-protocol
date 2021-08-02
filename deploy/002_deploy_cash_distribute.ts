import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';
import { ethers, network } from 'hardhat';
import { BigNumber } from 'ethers';
const TEST_MONEY = ethers.utils.parseEther('100000');
const DECIMALS = ethers.utils.parseEther('1');
import config from '../config/config'
import { wait } from '../scripts/utils'


const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy } = deployments;

    const { deployer } = await getNamedAccounts();
    let cash = await hre.ethers.getContract("Cash", deployer);
    console.log("cach address", cash.address)

    const netConf = config[await hre.getChainId()]
    let isTokenNew: boolean;
    for (let name in netConf.tokens) {
        const item = netConf.tokens[name]
        console.log(name, item)
        isTokenNew = (await deploy(`KYC${name}POOL`, {
            from: deployer,
            args: [
                cash.address,
                item.addr,
                item.start,
            ],
            contract: "KYCUSDCPool"
        })).newlyDeployed
        console.log(`KYC${name}POOL`, "done")
        if (isTokenNew) {
            let pool = await hre.ethers.getContract(`KYC${name}POOL`, deployer)
            let tx = await pool.setRewardDistribution(deployer)
            await new Promise(resolve => setTimeout(resolve, 3000));
            console.log(tx.hash)
            await wait(ethers, tx.hash, "setRewardDistribution")
        }
    }
};
export default func;
func.tags = ["distribute"]
