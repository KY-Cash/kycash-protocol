// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0 <0.8.0;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';
import {SafeMath} from '@openzeppelin/contracts/math/SafeMath.sol';
import {UniswapV2Library} from '../lib/UniswapV2Library.sol';
import {Math} from '../utils/Math.sol';
import {SimpleERCFund} from './SimpleERCFund.sol';
import {IUniswapV2Router01} from '../interfaces/IUniswapV2Router.sol';
import {Operator} from '../access/Operator.sol';
import {ISimpleERCFund} from './ISimpleERCFund.sol';

contract TradeERCFund is ISimpleERCFund, Operator {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    address public cash;
    address public usdt;
    address public factory;
    address public swap;
    address public treasury;
    uint256 public minSellPrice = 105e16;

    modifier onlyTreasury() {
        require(_msgSender() == treasury, 'SeigniorageProxy: invalid treasury');

        _;
    }

    constructor(
        address _cash,
        address _usdt,
        address _factory,
        address _swap
    ) {
        cash = _cash;
        usdt = _usdt;
        factory = _factory;
        swap = _swap;
    }

    function setMinSellPrice(uint256 _minSellPrice) public onlyOperator {
        minSellPrice = _minSellPrice;
    }

    function setTreasury(address _treasury) public onlyOperator {
        treasury = _treasury;
    }

    function deposit(
        address token,
        uint256 amount,
        string memory reason
    ) public override onlyTreasury {
        IERC20(token).safeTransferFrom(_msgSender(), address(this), amount);
        _sellCashToPrice(1e18, minSellPrice);
        emit Deposit(_msgSender(), block.timestamp, reason);
    }

    function _sellCashToPrice(uint256 _price, uint256 _minSellPrice) internal {
        (uint256 cashReserve, uint256 usdtReserve) = UniswapV2Library
            .getReserves(factory, cash, usdt);

        if (usdtReserve.mul(1e18).div(cashReserve) <= _minSellPrice) {
            return;
        }

        uint256 sellAmount = Math
            .sqrt(cashReserve.mul(usdtReserve).div(1e18).mul(_price))
            .sub(cashReserve);
        uint256 accountCachBalance = IERC20(cash).balanceOf(address(this));
        if (accountCachBalance == 0 || sellAmount <= 0) {
            return;
        }
        sellAmount = Math.min(sellAmount, accountCachBalance);

        IERC20(cash).approve(swap, sellAmount);
        address[] memory path = new address[](2);
        path[0] = cash;
        path[1] = usdt;
        IUniswapV2Router01(swap).swapExactTokensForTokens(
            sellAmount,
            0,
            path,
            address(this),
            block.timestamp + 1 hours
        );
    }

    function sellCashToPrice(uint256 _price, uint256 _minSellPrice)
        public
        onlyOperator
    {
        _sellCashToPrice(_price, _minSellPrice);
    }

    function buyCash(uint256 amount) public onlyOperator {
        uint256 accountUSDT = IERC20(usdt).balanceOf(address(this));
        amount = Math.min(amount, accountUSDT);
        IERC20(usdt).approve(swap, amount);
        address[] memory path = new address[](2);
        path[0] = usdt;
        path[1] = cash;
        IUniswapV2Router01(swap).swapExactTokensForTokens(
            amount,
            0,
            path,
            address(this),
            block.timestamp + 1 hours
        );
    }

    function withdraw(
        address token,
        uint256 amount,
        address to,
        string memory reason
    ) public override onlyOperator {
        IERC20(token).safeTransfer(to, amount);
        emit Withdrawal(_msgSender(), to, block.timestamp, reason);
    }

    event Deposit(address indexed from, uint256 indexed at, string reason);
    event Withdrawal(
        address indexed from,
        address indexed to,
        uint256 indexed at,
        string reason
    );
}
