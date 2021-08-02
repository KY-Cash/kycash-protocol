import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';
import { ethers, network } from 'hardhat';
import { BigNumber } from 'ethers';
import { REWARD_AMOUNT } from '../deploy.config'
const TEST_MONEY = ethers.utils.parseEther('100000');
const DECIMALS = ethers.utils.parseEther('1');
import config from '../config/config'
import { wait } from '../scripts/utils'


const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy } = deployments;

    const { deployer } = await getNamedAccounts();

    const netConf = config[await hre.getChainId()]
    let isTokenNew: boolean;
    await deploy(`Cash`, {
        from: deployer,
        args: [
        ],
        contract: "Cash"
    })
    let cash = await hre.ethers.getContract("Cash", deployer);
    if (network.name != "mainnet") {
        if (await cash.balanceOf(deployer) < TEST_MONEY) {
            let tx = await cash.mint(deployer, TEST_MONEY);
            await wait(ethers, tx.hash, "mint")
        }
    }
};
export default func;
func.tags = ["token"]
