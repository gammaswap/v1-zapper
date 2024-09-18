// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";

import "./interfaces/ILPZapper.sol";
import "./BaseZapper.sol";

/// @title LPZapper Smart Contract
/// @author Daniel D. Alcarraz (https://github.com/0xDanr)
/// @dev Zaps in/out single token or ETH into GammaPool
contract LPZapper is Initializable, UUPSUpgradeable, Ownable2Step, ILPZapper, BaseZapper {

    /// @dev address of PositionManager used with GammaPool
    address public immutable positionManager;

    /// @dev See {BaseZapper-constructor}
    constructor(address _WETH, address _factory, address _dsFactory, address _positionManager, address _mathLib, address _uniV2Router, address _sushiRouter, address _dsRouter, address _uniV3Router)
        BaseZapper(_WETH, _factory, _dsFactory, _mathLib, _uniV2Router, _sushiRouter, _dsRouter, _uniV3Router) {
        positionManager = _positionManager;
    }

    /// @dev Initialize LPZapper when used as a proxy contract
    function initialize() public virtual initializer {
        require(owner() == address(0), "LP_ZAPPER: INITIALIZED");
        _transferOwnership(msg.sender);
    }

    /// @dev See {ILPZapper-zapInETH}.
    function zapInETH(IPositionManager.DepositReservesParams memory params, LPSwapParams memory lpSwap, FundSwapParams memory fundSwap) external override virtual payable {
        require(msg.value > 0, "LP_ZAPPER: ZERO_ETH");

        uint256 fundAmount = msg.value;

        IWETH(WETH).deposit{value: fundAmount}(); // wrap only what is needed

        zapIn(WETH, fundAmount, params, lpSwap, fundSwap);
    }

    /// @dev See {ILPZapper-zapInToken}.
    function zapInToken(address tokenIn, uint256 fundAmount, IPositionManager.DepositReservesParams memory params, LPSwapParams memory lpSwap, FundSwapParams memory fundSwap) external override virtual {
        require(fundAmount > 1000, "LP_ZAPPER: INVALID_FUND_AMOUNT");
        require(tokenIn != address(0), "LP_ZAPPER: ZERO_ADDRESS");

        GammaSwapLibrary.safeTransferFrom(tokenIn, msg.sender, address(this), fundAmount);

        zapIn(tokenIn, fundAmount, params, lpSwap, fundSwap);
    }

    /// @dev If tokenIn is not token0 or token1 of GammaPool, convert entire fundAmount into token0 or token1 using instructions in fundSwap, ignoring slippage
    /// @dev Sells part of tokenIn into either token0 or token1 to match the same ratio of token0 to token1 in CFMM to deposit into GammaPool
    /// @dev Swaps do not control for slippage. Slippage is controlled through DepositReservesParams.amountsMin. Therefore, user must calculate minimum expected amounts to deposit
    /// @dev If uniV3Path is not set in lpSwap then use lpSwap.path parameter. If lpSwap.amount is not set or lpSwap.path is not set, use CFMM's own token path and calculate necessary quantities to deposit all tokens
    /// @dev See {ILPZapper-zapIn}.
    function zapIn(address tokenIn, uint256 fundAmount, IPositionManager.DepositReservesParams memory params, LPSwapParams memory lpSwap, FundSwapParams memory fundSwap) public virtual {
        require(params.to != address(0), "LP_ZAPPER: INVALID_PARAM_TO");
        require(params.cfmm != address(0), "LP_ZAPPER: INVALID_PARAM_CFMM");

        address token0 = ICPMM(params.cfmm).token0();
        address token1 = ICPMM(params.cfmm).token1();

        // convert everything into one of the pool's token if it's not
        if(tokenIn != token0 && tokenIn != token1) {
            (tokenIn, fundAmount) = _swapTokenInFull(token0, token1, tokenIn, fundAmount, 0, fundSwap.protocolId, fundSwap.path, fundSwap.uniV3Path);
        }

        require(tokenIn == token0 || tokenIn == token1, "LP_ZAPPER: INVALID_TOKEN_IN");

        address tokenOut = tokenIn == token0 ? token1 : token0;

        if(lpSwap.uniV3Path.length > 0) {
            require(tokenOut == _getTokenOut(lpSwap.uniV3Path), "LP_ZAPPER: INVALID_TOKEN_OUT");
            require(lpSwap.amount > 0 && fundAmount > lpSwap.amount, "LP_ZAPPER: INVALID_SELL_AMOUNT");
            _uniV3Swap(tokenIn, lpSwap.amount, 0, lpSwap.uniV3Path, address(this));
        } else {
            if(lpSwap.amount == 0 || lpSwap.path.length < 2) {
                lpSwap.path = new address[](2);
                lpSwap.path[0] = tokenIn;
                lpSwap.path[1] = tokenOut;
                lpSwap.protocolId = params.protocolId;
                ICPMM(params.cfmm).sync();
                lpSwap.amount = _calcSellAmount(params.cfmm, params.protocolId, token0, token1, tokenIn, fundAmount);
            }

            require(lpSwap.amount > 0, "LP_ZAPPER: INVALID_SELL_AMOUNT");
            require(tokenOut == lpSwap.path[lpSwap.path.length - 1], "LP_ZAPPER: INVALID_TOKEN_OUT");
            _swap(tokenIn, lpSwap.amount, 0, lpSwap.path, lpSwap.protocolId, address(this));
        }

        params.amountsDesired = new uint256[](2);
        params.amountsDesired[0] = GammaSwapLibrary.balanceOf(token0, address(this));
        params.amountsDesired[1] = GammaSwapLibrary.balanceOf(token1, address(this));
        params.deadline = block.timestamp;

        GammaSwapLibrary.safeApprove(token0, positionManager, params.amountsDesired[0]);
        GammaSwapLibrary.safeApprove(token1, positionManager, params.amountsDesired[1]);

        IPositionManager(positionManager).depositReserves(params); //params must be to send to here

        fundAmount = GammaSwapLibrary.balanceOf(token0, address(this));
        if(fundAmount > 0) GammaSwapLibrary.safeTransfer(token0, params.to, fundAmount);

        fundAmount = GammaSwapLibrary.balanceOf(token1, address(this));
        if(fundAmount > 0) GammaSwapLibrary.safeTransfer(token1, params.to, fundAmount);
    }

    /// @dev See {ILPZapper-zapOutETH}.
    function zapOutETH(IPositionManager.WithdrawReservesParams memory params, LPSwapParams memory lpSwap0, LPSwapParams memory lpSwap1, bool isCFMMWithdrawal) external override virtual {
        require(params.to != address(0), "LP_ZAPPER: INVALID_PARAM_TO");

        if(ICPMM(params.cfmm).token0() == WETH) {
            require((lpSwap1.path.length > 0 && lpSwap1.path[lpSwap1.path.length - 1] == WETH) || (lpSwap1.uniV3Path.length > 0 && _getTokenOut(lpSwap1.uniV3Path) == WETH),"LP_ZAPPER: PATH1_EXIT_NOT_WETH");
        } else if(ICPMM(params.cfmm).token1() == WETH) {
            require((lpSwap0.path.length > 0 && lpSwap0.path[lpSwap0.path.length - 1] == WETH) || (lpSwap0.uniV3Path.length > 0 && _getTokenOut(lpSwap0.uniV3Path) == WETH),"LP_ZAPPER: PATH0_EXIT_NOT_WETH");
        } else {
            require((lpSwap0.path.length > 0 && lpSwap0.path[lpSwap0.path.length - 1] == WETH) || (lpSwap0.uniV3Path.length > 0 && _getTokenOut(lpSwap0.uniV3Path) == WETH),"LP_ZAPPER: PATH0_EXIT_NOT_WETH");
            require((lpSwap1.path.length > 0 && lpSwap1.path[lpSwap1.path.length - 1] == WETH) || (lpSwap1.uniV3Path.length > 0 && _getTokenOut(lpSwap1.uniV3Path) == WETH),"LP_ZAPPER: PATH1_EXIT_NOT_WETH");
        }

        address to = params.to;
        params.to = address(this);

        zapOutToken(params, lpSwap0, lpSwap1, isCFMMWithdrawal);

        unwrapWETH(0, to);
    }

    /// @dev See {ILPZapper-zapOutToken}.
    /// @notice Slippage of conversion of tokens after withdrawal is handled by the amount parameter of the LPSwapParams structs lpSwap0 and lpSwap1
    /// @notice If no instructions are provided in lpSwap0 and/or lpSwap1 then the token is withdrawn as the token of the GammaPool
    function zapOutToken(IPositionManager.WithdrawReservesParams memory params, LPSwapParams memory lpSwap0, LPSwapParams memory lpSwap1, bool isCFMMWithdrawal) public override virtual {
        require(params.to != address(0), "LP_ZAPPER: INVALID_PARAM_TO");
        require(params.cfmm != address(0), "LP_ZAPPER: INVALID_PARAM_CFMM");
        address to = params.to;
        params.to = address(this);

        (address lpToken, address router) = isCFMMWithdrawal ?
            (params.cfmm, _getCFMMRouter(params.protocolId)) :
            (getGammaPoolAddress(params.cfmm, params.protocolId), positionManager);

        GammaSwapLibrary.safeTransferFrom(lpToken, msg.sender, address(this), params.amount);
        GammaSwapLibrary.safeApprove(lpToken, router, params.amount);

        address[] memory lpTokens = new address[](2);
        lpTokens[0] = ICPMM(params.cfmm).token0();
        lpTokens[1] = ICPMM(params.cfmm).token1();

        uint256[] memory reserves;
        if(isCFMMWithdrawal) {
            reserves = new uint256[](2);
            (reserves[0], reserves[1]) = IDeltaSwapRouter02(router).removeLiquidity(lpTokens[0], lpTokens[1], params.amount,
                params.amountsMin[0], params.amountsMin[1], params.to, block.number); //params must be to send to here
        } else {
            (reserves,) = IPositionManager(router).withdrawReserves(params); //params must be to send to here
        }

        if(lpSwap0.path.length > 0 || lpSwap0.uniV3Path.length > 0) {
            if(lpSwap0.uniV3Path.length > 0) {
                _uniV3Swap(lpTokens[0], reserves[0], lpSwap0.amount, lpSwap0.uniV3Path, to);
            } else {
                _swap(lpTokens[0], reserves[0], lpSwap0.amount, lpSwap0.path, lpSwap0.protocolId, to);
            }
        } else {
            GammaSwapLibrary.safeTransfer(lpTokens[0], to, reserves[0]);
        }
        if(lpSwap1.path.length > 0 || lpSwap1.uniV3Path.length > 0) {
            if(lpSwap1.uniV3Path.length > 0) {
                _uniV3Swap(lpTokens[1], reserves[1], lpSwap1.amount, lpSwap1.uniV3Path, to);
            } else {
                _swap(lpTokens[1], reserves[1], lpSwap1.amount, lpSwap1.path, lpSwap1.protocolId, to);
            }
        } else {
            GammaSwapLibrary.safeTransfer(lpTokens[1], to, reserves[1]);
        }
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
