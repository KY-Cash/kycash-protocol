// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0 <0.8.0;

import {Address} from '@openzeppelin/contracts/utils/Address.sol';
import {Math} from '@openzeppelin/contracts/math/Math.sol';
import {SafeMath} from '@openzeppelin/contracts/math/SafeMath.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';
import {ReentrancyGuard} from '@openzeppelin/contracts/utils/ReentrancyGuard.sol';

import {ICurve} from '../curve/Curve.sol';
import {IOracle} from '../oracle/Oracle.sol';
import {IBasisAsset} from '../assets/IBasisAsset.sol';
import {ISimpleERCFund} from '../cdf/ISimpleERCFund.sol';
import {Babylonian} from '../lib/Babylonian.sol';
import {Operator} from '../access/Operator.sol';
import {Epoch} from '../utils/Epoch.sol';
import {SeigniorageProxy} from './SeigniorageProxy.sol';
import {ContractGuard} from '../utils/ContractGuard.sol';
import {TreasuryState} from './TreasuryState.sol';

/**
 * @title Basis Cash Treasury contract
 * @notice Monetary policy logic to adjust supplies of basis cash assets
 * @author Summer Smith & Rick Sanchez
 */
contract Treasury is TreasuryState, ContractGuard {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using Address for address;

    /* ========== CONSTRUCTOR ========== */

    constructor(
        address _cash,
        address _bond,
        address _share,
        address _bOracle,
        address _sOracle,
        address _seigniorageProxy,
        address _fund,
        address _capital,
        address _curve,
        uint256 _startTime,
        uint256 _period
    ) Epoch(_period, _startTime, 0) {
        cash = _cash;
        bond = _bond;
        share = _share;
        curve = _curve;

        bOracle = _bOracle;
        sOracle = _sOracle;
        seigniorageProxy = _seigniorageProxy;

        fund = _fund;
        capital = _capital;

        cashPriceOne = 10**18;
    }

    /* =================== Modifier =================== */

    modifier checkMigration() {
        require(!migrated, 'Treasury: migrated');

        _;
    }

    modifier updatePrice() {
        _;

        _updateCashPrice();
    }

    /* ========== VIEW FUNCTIONS ========== */

    // budget
    function getReserve() public view returns (uint256) {
        return accumulatedSeigniorage;
    }

    function circulatingSupply() public view returns (uint256) {
        return IERC20(cash).totalSupply().sub(accumulatedSeigniorage);
    }

    function getCeilingPrice() public view returns (uint256) {
        return ICurve(curve).calcCeiling(circulatingSupply());
    }

    // oracle
    function getbOraclePrice() public view returns (uint256) {
        return _getCashPrice(bOracle);
    }

    function getsOraclePrice() public view returns (uint256) {
        return _getCashPrice(sOracle);
    }

    function _getCashPrice(address oracle) internal view returns (uint256) {
        try IOracle(oracle).consult(cash, 1e18) returns (uint256 price) {
            return price;
        } catch {
            revert('Treasury: failed to consult cash price from the oracle');
        }
    }

    /* ========== MUTABLE FUNCTIONS ========== */

    function _updateCashPrice() internal {
        if (Epoch(bOracle).callable()) {
            try IOracle(bOracle).update() {} catch {}
        }
        if (Epoch(sOracle).callable()) {
            try IOracle(sOracle).update() {} catch {}
        }
    }

    function allocateSeigniorage()
        external
        onlyOneBlock
        checkMigration
        checkStartTime
        checkEpoch
        checkOperator
    {
        _updateCashPrice();
        uint256 cashPrice = _getCashPrice(sOracle);
        if (cashPrice <= getCeilingPrice()) {
            return; // just advance epoch instead revert
        }

        // circulating supply
        uint256 percentage = cashPrice.sub(cashPriceOne);
        uint256 seigniorage = circulatingSupply().mul(percentage).div(1e18);
        IBasisAsset(cash).mint(address(this), seigniorage);
        // ======================== BIP-3
        uint256 fundReserve = seigniorage.mul(fundAllocationRate).div(100);
        if (fundReserve > 0) {
            IERC20(cash).safeIncreaseAllowance(fund, fundReserve);
            ISimpleERCFund(fund).deposit(
                cash,
                fundReserve,
                'Treasury: Seigniorage Allocation to Fund'
            );
            emit FundedToCommunityFund(block.timestamp, fundReserve);
        }

        uint256 capitalReserve = seigniorage.mul(capitalAllocationRate).div(
            100
        );
        if (capitalReserve > 0) {
            IERC20(cash).safeIncreaseAllowance(capital, capitalReserve);
            ISimpleERCFund(capital).deposit(
                cash,
                capitalReserve,
                'Treasury: Seigniorage Allocation to Capital'
            );
            emit FundedToCommunityFund(block.timestamp, capitalReserve);
        }

        seigniorage = seigniorage.sub(fundReserve);
        seigniorage = seigniorage.sub(capitalReserve);

        if (seigniorage > 0) {
            IERC20(cash).safeIncreaseAllowance(seigniorageProxy, seigniorage);
            SeigniorageProxy(seigniorageProxy).allocateSeigniorage(seigniorage);
            emit SeigniorageDistributed(block.timestamp, seigniorage);
        }
    }

    // CORE
    event RedeemedBonds(address indexed from, uint256 amount);
    event BoughtBonds(address indexed from, uint256 amount);
    event TreasuryFunded(uint256 timestamp, uint256 seigniorage);
    event SeigniorageDistributed(uint256 timestamp, uint256 seigniorage);
    event FundedToCommunityFund(uint256 timestamp, uint256 seigniorage);
}
