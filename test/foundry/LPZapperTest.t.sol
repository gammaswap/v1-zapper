// SPDX-License-Identifier: GPL-v3
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@gammaswap/v1-core/contracts/libraries/GSMath.sol";
import "./fixtures/CPMMGammaSwapSetup.sol";
import "../../contracts/LPZapper.sol";
import "../../contracts/test/TestLPZapper.sol";

contract LPZapperTest is CPMMGammaSwapSetup {

    struct TestParams {
        address lpToken;
        address token0;
        address token1;
        uint256 balWETH;
        uint256 balUSDC;
        uint256 balWETH6;
        uint256 balUSDC6;
        uint256 balETH;
    }

    ILPZapper lpZapper;
    address user;

    function setUp() public {
        super.initCPMMGammaSwap(true);
        user = vm.addr(3);

        GammaSwapLibrary.safeTransferETH(address(weth9), 1000_000*1e18);

        lpZapper = new TestLPZapper(address(weth9), address(factory), address(cfmmFactory), address(posMgr), address(mathLib), address(uniRouter), address(0), address(uniRouter), address(0));
        deal(address(weth9), user, 1000*1e18);
        deal(address(weth), user, 1000_000*1e18);
        deal(address(usdc), user, 1000_000*1e18);

        depositLiquidityInCFMM(addr2, 100e18, 100e18);
        depositLiquidityInPool(addr2);

        // 18x18 = usdc/weth9
        depositLiquidityInCFMMByToken(address(usdc), address(weth9), 100*1e18, 100*1e18, addr1);
        depositLiquidityInCFMMByToken(address(usdc), address(weth9), 100*1e18, 100*1e18, addr2);
        depositLiquidityInPoolFromCFMM(poolW9, cfmmW9, addr2);

        // 18x6 = usdc/weth6
        depositLiquidityInCFMMByToken(address(usdc), address(weth6), 100*1e18, 100*1e6, addr1);
        depositLiquidityInCFMMByToken(address(usdc), address(weth6), 100*1e18, 100*1e6, addr2);
        depositLiquidityInPoolFromCFMM(pool18x6, cfmm18x6, addr2);

        // 6x6 = weth6/usdc6
        depositLiquidityInCFMMByToken(address(usdc6), address(weth6), 100*1e6, 100*1e6, addr1);
        depositLiquidityInCFMMByToken(address(usdc6), address(weth6), 100*1e6, 100*1e6, addr2);
        depositLiquidityInPoolFromCFMM(pool6x6, cfmm6x6, addr2);

        // 6x18 = usdc6/weth
        depositLiquidityInCFMMByToken(address(usdc6), address(weth), 100*1e6, 100*1e18, addr1);
        depositLiquidityInCFMMByToken(address(usdc6), address(weth), 100*1e6, 100*1e18, addr2);
        depositLiquidityInPoolFromCFMM(pool6x18, cfmm6x18, addr2);
    }

    function testGetTokenOutErrors() public {
        address payable addr = payable(address(lpZapper));

        bytes memory pathErr = hex'0c880f6761f1af8d9aa9c466984b80dab9a8c9e8000bb8';
        vm.expectRevert("toAddress_outOfBounds");
        TestLPZapper(addr).getTokenOut(pathErr);

        pathErr = hex'0c880f6761f1af8d9aa9c466984b80dab9a8c9e8000b';
        vm.expectRevert();
        TestLPZapper(addr).getTokenOut(pathErr);

        pathErr = hex'0c880f6761f1af8d9aa9c466984b80dab9a8c9e800';
        vm.expectRevert();
        TestLPZapper(addr).getTokenOut(pathErr);

        pathErr = hex'0c880f6761f1af8d9aa9c466984b80dab9a8c9e8';//000bb8';
        vm.expectRevert();
        TestLPZapper(addr).getTokenOut(pathErr);

        pathErr = hex'000bb882af49447d8a07e3bd95bd0d56f35241523fbab1';//000bb8';
        vm.expectRevert("toAddress_outOfBounds");
        TestLPZapper(addr).getTokenOut(pathErr);

        pathErr = hex'000b82af49447d8a07e3bd95bd0d56f35241523fbab1';//000b';
        vm.expectRevert();
        TestLPZapper(addr).getTokenOut(pathErr);

        pathErr = hex'0082af49447d8a07e3bd95bd0d56f35241523fbab1';//00';
        vm.expectRevert();
        TestLPZapper(addr).getTokenOut(pathErr);

        pathErr = hex'984b80dab9a8c9e8000bb882af49447d8a07e3bd95bd0d';
        vm.expectRevert("toAddress_outOfBounds");
        TestLPZapper(addr).getTokenOut(pathErr);
    }

    function testGetTokenOut() public {
        address payable addr = payable(address(lpZapper));

        bytes memory path0 = hex'0c880f6761f1af8d9aa9c466984b80dab9a8c9e8000bb882af49447d8a07e3bd95bd0d56f35241523fbab1';
        address tokenOut0 = TestLPZapper(addr).getTokenOut(path0);
        assertEq(tokenOut0, address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1));
        console.log(tokenOut0);

        bytes memory path1 = hex'0c880f6761f1af8d9aa9c466984b80dab9a8c9e8000bb882af49447d8a07e3bd95bd0d56f35241523fbab10001f4af88d065e77c8cc2239327c5edb3a432268e5831';
        address tokenOut1 = TestLPZapper(addr).getTokenOut(path1);
        assertEq(tokenOut1,address(0xaf88d065e77c8cC2239327C5EDb3A432268e5831));
        console.log(tokenOut1);

        bytes memory path2 = hex'0c880f6761f1af8d9aa9c466984b80dab9a8c9e8000bb882af49447d8a07e3bd95bd0d56f35241523fbab10001f4af88d065e77c8cc2239327c5edb3a432268e583100010076991314cEE341ebE37e6E2712cb04F5d56dE355';
        address tokenOut2 = TestLPZapper(addr).getTokenOut(path2);
        assertEq(tokenOut2,address(0x76991314cEE341ebE37e6E2712cb04F5d56dE355));
        console.log(tokenOut2);

        bytes memory path3 = hex'0c880f6761f1af8d9aa9c466984b80dab9a8c9e8000bb882af49447d8a07e3bd95bd0d56f35241523fbab10001f4af88d065e77c8cc2239327c5edb3a432268e583100010076991314cEE341ebE37e6E2712cb04F5d56dE355000100F6D9C101ceeA72655A13a8Cf1C88c1949Ed399bc';
        address tokenOut3 = TestLPZapper(addr).getTokenOut(path3);
        assertEq(tokenOut3,address(0xF6D9C101ceeA72655A13a8Cf1C88c1949Ed399bc));
        console.log(tokenOut3);
    }

    function testLPZapperOwner() public {
        address payable addr = payable(address(lpZapper));
        assertEq(LPZapper(addr).owner(), address(this));

        vm.expectRevert("LP_ZAPPER: INITIALIZED");
        LPZapper(addr).initialize();
    }

    function testZapInETH(uint16 fundAmt) public {
        fundAmt = fundAmt < 100 ? 100 : fundAmt;

        GammaSwapLibrary.safeTransferETH(user, 1000*1e18);

        vm.startPrank(user);

        uint256[] memory amountsMin = new uint256[](2);
        IPositionManager.DepositReservesParams memory params = IPositionManager.DepositReservesParams({
            protocolId: 1,
            cfmm: address(cfmmW9),
            to: user,
            deadline: block.timestamp,
            amountsDesired: new uint256[](0),
            amountsMin: amountsMin
        });

        ILPZapper.LPSwapParams memory lpSwap = ILPZapper.LPSwapParams({
            amount: 0,
            protocolId: 0,
            path: new address[](0),
            uniV3Path: new bytes(0)
        });

        ILPZapper.FundSwapParams memory fundSwap = ILPZapper.FundSwapParams({
            protocolId: 0,
            path: new address[](0),
            uniV3Path: new bytes(0)
        });

        uint256 fundAmount = uint256(fundAmt) * 1e14;
        uint256 expFundAmount = fundAmount;

        uint256 totalSupply = poolW9.totalSupply();
        uint256 prevGSLPBalance = poolW9.balanceOf(user);

        vm.expectRevert("LP_ZAPPER: ZERO_ETH");
        lpZapper.zapInETH(params, lpSwap, fundSwap);

        lpZapper.zapInETH{value: fundAmount}(params, lpSwap, fundSwap);

        assertGt(poolW9.totalSupply(), totalSupply);
        assertGt(poolW9.balanceOf(user), prevGSLPBalance);

        IGammaPool.PoolData memory poolData = poolW9.getPoolData();
        uint256 userLPBalance = poolW9.balanceOf(user) * poolData.LP_TOKEN_BALANCE / poolW9.totalSupply();
        (uint256 reserve0, uint256 reserve1,) = IDeltaSwapPair(cfmmW9).getReserves();
        totalSupply = IERC20(cfmmW9).totalSupply();

        assertApproxEqRel(expFundAmount / 2, userLPBalance * reserve0 / totalSupply, 15e16);
        assertApproxEqRel(expFundAmount / 2, userLPBalance * reserve1 / totalSupply, 15e16);
    }

    function testZapInETHToTokens(uint16 fundAmt) public {
        fundAmt = fundAmt < 100 ? 100 : fundAmt;

        GammaSwapLibrary.safeTransferETH(user, 1000*1e18);

        vm.startPrank(user);

        uint256[] memory amountsMin = new uint256[](2);
        IPositionManager.DepositReservesParams memory params = IPositionManager.DepositReservesParams({
            protocolId: 1,
            cfmm: address(cfmm),
            to: user,
            deadline: block.timestamp,
            amountsDesired: new uint256[](0),
            amountsMin: amountsMin
        });

        ILPZapper.LPSwapParams memory lpSwap = ILPZapper.LPSwapParams({
            amount: 0,
            protocolId: 0,
            path: new address[](0),
            uniV3Path: new bytes(0)
        });

        ILPZapper.FundSwapParams memory fundSwap = ILPZapper.FundSwapParams({
            protocolId: 1,
            path: new address[](2),
            uniV3Path: new bytes(0)
        });

        fundSwap.path[0] = address(weth9);
        fundSwap.path[1] = address(usdc);

        uint256 fundAmount = uint256(fundAmt) * 1e14;
        uint256 expFundAmount = fundAmount;

        uint256 totalSupply = pool.totalSupply();
        uint256 prevGSLPBalance = pool.balanceOf(user);

        lpZapper.zapInETH{value: fundAmount}(params, lpSwap, fundSwap);

        assertGt(pool.totalSupply(), totalSupply);
        assertGt(pool.balanceOf(user), prevGSLPBalance);

        IGammaPool.PoolData memory poolData = pool.getPoolData();
        uint256 userLPBalance = pool.balanceOf(user) * poolData.LP_TOKEN_BALANCE / pool.totalSupply();
        (uint256 reserve0, uint256 reserve1,) = IDeltaSwapPair(cfmm).getReserves();
        totalSupply = IERC20(cfmm).totalSupply();

        assertApproxEqRel(expFundAmount / 2, userLPBalance * reserve0 / totalSupply, 15e16);
        assertApproxEqRel(expFundAmount / 2, userLPBalance * reserve1 / totalSupply, 15e16);
    }

    function testZapOutETH(uint8 percent, bool isCFMMWithdrawal) public {
        percent = percent < 10 ? 10 : percent;
        percent = percent > 100 ? 100 : percent;

        vm.startPrank(user);

        uint256[] memory amountsMin = new uint256[](2);
        IPositionManager.DepositReservesParams memory depositParams = IPositionManager.DepositReservesParams({
            protocolId: 1,
            cfmm: address(cfmmW9),
            to: user,
            deadline: block.timestamp,
            amountsDesired: new uint256[](2),
            amountsMin: amountsMin
        });
        depositParams.amountsDesired[0] = 1e18;
        depositParams.amountsDesired[1] = 1e18;

        TestParams memory _params = TestParams({
            lpToken: address(poolW9),
            token0: ICPMM(cfmmW9).token0(),
            token1: ICPMM(cfmmW9).token1(),
            balWETH: 0,
            balUSDC: 0,
            balWETH6: 0,
            balUSDC6: 0,
            balETH: 0
        });

        if(isCFMMWithdrawal) {
            _params.lpToken = address(cfmmW9);
            IERC20(_params.token0).approve(address(uniRouter), 1e18);
            IERC20(_params.token1).approve(address(uniRouter), 1e18);

            uniRouter.addLiquidity(_params.token0, _params.token1, 1e18, 1e18, 0, 0, user, type(uint256).max);
        } else {
            IERC20(_params.token0).approve(address(posMgr), 1e18);
            IERC20(_params.token1).approve(address(posMgr), 1e18);

            posMgr.depositReserves(depositParams);
        }

        uint256 gslpBalance = IERC20(_params.lpToken).balanceOf(user);

        uint256 withdrawAmt = gslpBalance * percent / 100;
        assertGt(withdrawAmt, 0);

        IPositionManager.WithdrawReservesParams memory params = IPositionManager.WithdrawReservesParams({
            protocolId: 1,
            cfmm: address(cfmmW9),
            amount: withdrawAmt,
            to: user,
            deadline: block.timestamp,
            amountsMin: new uint256[](2)
        });

        ILPZapper.LPSwapParams memory lpSwap0 = ILPZapper.LPSwapParams({
            amount: 0,
            protocolId: 0,
            path: new address[](0),
            uniV3Path: new bytes(0)
        });

        ILPZapper.LPSwapParams memory lpSwap1 = ILPZapper.LPSwapParams({
            amount: 0,
            protocolId: 0,
            path: new address[](0),
            uniV3Path: new bytes(0)
        });

        GammaSwapLibrary.safeApprove(_params.lpToken, address(lpZapper), withdrawAmt);

        if(_params.token0 == address(weth9)) {
            vm.expectRevert("LP_ZAPPER: PATH1_EXIT_NOT_WETH");
            isCFMMWithdrawal ? lpZapper.dsZapOutETH(params, lpSwap0, lpSwap1) : lpZapper.zapOutETH(params, lpSwap0, lpSwap1);
            lpSwap1.protocolId = 1;
            lpSwap1.path = new address[](2);
            lpSwap1.path[0] = _params.token1;
            lpSwap1.path[1] = _params.token0;
        } else {
            vm.expectRevert("LP_ZAPPER: PATH0_EXIT_NOT_WETH");
            isCFMMWithdrawal ? lpZapper.dsZapOutETH(params, lpSwap0, lpSwap1) :lpZapper.zapOutETH(params, lpSwap0, lpSwap1);
            lpSwap0.protocolId = 1;
            lpSwap0.path = new address[](2);
            lpSwap0.path[0] = _params.token0;
            lpSwap0.path[1] = _params.token1;
        }

        _params.balETH = address(user).balance;
        uint256 balToken0 = IERC20(_params.token0).balanceOf(user);
        uint256 balToken1 = IERC20(_params.token1).balanceOf(user);

        isCFMMWithdrawal ?lpZapper.dsZapOutETH(params, lpSwap0, lpSwap1) : lpZapper.zapOutETH(params, lpSwap0, lpSwap1);

        assertEq(gslpBalance - withdrawAmt, IERC20(_params.lpToken).balanceOf(user));
        assertEq(balToken0, IERC20(_params.token0).balanceOf(user));
        assertEq(balToken1, IERC20(_params.token1).balanceOf(user));
        assertGt(address(user).balance, _params.balETH);
        assertApproxEqRel(address(user).balance, 2e18 * uint256(percent) / 100, 15e15);
    }

    function testZapOutETHFromTokens(uint8 percent, bool isCFMMWithdrawal) public {
        percent = percent < 10 ? 10 : percent;
        percent = percent > 100 ? 100 : percent;

        vm.startPrank(user);

        uint256[] memory amountsMin = new uint256[](2);
        IPositionManager.DepositReservesParams memory depositParams = IPositionManager.DepositReservesParams({
            protocolId: 1,
            cfmm: address(cfmm),
            to: user,
            deadline: block.timestamp,
            amountsDesired: new uint256[](2),
            amountsMin: amountsMin
        });
        depositParams.amountsDesired[0] = 1e18;
        depositParams.amountsDesired[1] = 1e18;

        TestParams memory _params = TestParams({
            lpToken: address(pool),
            token0: ICPMM(cfmm).token0(),
            token1: ICPMM(cfmm).token1(),
            balWETH: 0,
            balUSDC: 0,
            balWETH6: 0,
            balUSDC6: 0,
            balETH: 0
        });

        if(isCFMMWithdrawal) {
            _params.lpToken = address(cfmm);
            IERC20(_params.token0).approve(address(uniRouter), 1e18);
            IERC20(_params.token1).approve(address(uniRouter), 1e18);

            uniRouter.addLiquidity(_params.token0, _params.token1, 1e18, 1e18, 0, 0, user, type(uint256).max);
        } else {
            IERC20(_params.token0).approve(address(posMgr), 1e18);
            IERC20(_params.token1).approve(address(posMgr), 1e18);

            posMgr.depositReserves(depositParams);
        }

        uint256 gslpBalance = IERC20(_params.lpToken).balanceOf(user);

        uint256 withdrawAmt = gslpBalance * percent / 100;
        assertGt(withdrawAmt, 0);

        IPositionManager.WithdrawReservesParams memory params = IPositionManager.WithdrawReservesParams({
            protocolId: 1,
            cfmm: address(cfmm),
            amount: withdrawAmt,
            to: user,
            deadline: block.timestamp,
            amountsMin: new uint256[](2)
        });

        ILPZapper.LPSwapParams memory lpSwap0 = ILPZapper.LPSwapParams({
            amount: 0,
            protocolId: 0,
            path: new address[](0),
            uniV3Path: new bytes(0)
        });

        ILPZapper.LPSwapParams memory lpSwap1 = ILPZapper.LPSwapParams({
            amount: 0,
            protocolId: 0,
            path: new address[](0),
            uniV3Path: new bytes(0)
        });

        GammaSwapLibrary.safeApprove(_params.lpToken, address(lpZapper), withdrawAmt);

        vm.expectRevert("LP_ZAPPER: PATH0_EXIT_NOT_WETH");
        isCFMMWithdrawal ? lpZapper.dsZapOutETH(params, lpSwap0, lpSwap1) : lpZapper.zapOutETH(params, lpSwap0, lpSwap1);

        lpSwap0.protocolId = 1;
        lpSwap0.path = new address[](3);
        lpSwap0.path[0] = _params.token0;
        lpSwap0.path[1] = _params.token1;
        lpSwap0.path[2] = address(weth9);

        vm.expectRevert("LP_ZAPPER: PATH1_EXIT_NOT_WETH");
        isCFMMWithdrawal ? lpZapper.dsZapOutETH(params, lpSwap0, lpSwap1) : lpZapper.zapOutETH(params, lpSwap0, lpSwap1);

        lpSwap1.protocolId = 1;
        lpSwap1.path = new address[](2);
        lpSwap1.path[0] = _params.token1;
        lpSwap1.path[1] = address(weth9);

        _params.balETH = address(user).balance;
        uint256 balToken0 = IERC20(_params.token0).balanceOf(user);
        uint256 balToken1 = IERC20(_params.token1).balanceOf(user);

        isCFMMWithdrawal ? lpZapper.dsZapOutETH(params, lpSwap0, lpSwap1) : lpZapper.zapOutETH(params, lpSwap0, lpSwap1);

        assertEq(gslpBalance - withdrawAmt, IERC20(_params.lpToken).balanceOf(user));
        assertEq(balToken0, IERC20(_params.token0).balanceOf(user));
        assertEq(balToken1, IERC20(_params.token1).balanceOf(user));
        assertGt(address(user).balance, _params.balETH);
        assertApproxEqRel(address(user).balance, 2e18 * uint256(percent) / 100, 15e15);
    }

    function testZapOut(uint8 swapPath, uint8 percent, bool isCFMMWithdrawal) public {
        percent = percent < 10 ? 10 : percent;
        percent = percent > 100 ? 100 : percent;

        uint256[] memory amountsMin = new uint256[](2);
        IPositionManager.DepositReservesParams memory depositParams = IPositionManager.DepositReservesParams({
            protocolId: 1,
            cfmm: address(cfmm),
            to: user,
            deadline: block.timestamp,
            amountsDesired: new uint256[](2),
            amountsMin: amountsMin
        });
        depositParams.amountsDesired[0] = 1e18;
        depositParams.amountsDesired[1] = 1e18;

        TestParams memory _params = TestParams({
            lpToken: address(pool),
            token0: ICPMM(cfmm).token0(),
            token1: ICPMM(cfmm).token1(),
            balWETH: 0,
            balUSDC: 0,
            balWETH6: 0,
            balUSDC6: 0,
            balETH: 0
        });

        if(isCFMMWithdrawal) {
            _params.lpToken = address(cfmm);
            IERC20(_params.token0).approve(address(uniRouter), 1e18);
            IERC20(_params.token1).approve(address(uniRouter), 1e18);

            uniRouter.addLiquidity(_params.token0, _params.token1, 1e18, 1e18, 0, 0, user, type(uint256).max);
        } else {
            IERC20(_params.token0).approve(address(posMgr), 1e18);
            IERC20(_params.token1).approve(address(posMgr), 1e18);

            posMgr.depositReserves(depositParams);
        }

        uint256 gslpBalance = IERC20(_params.lpToken).balanceOf(user);

        uint256 withdrawAmt = gslpBalance * percent / 100;

        IPositionManager.WithdrawReservesParams memory params = IPositionManager.WithdrawReservesParams({
            protocolId: 1,
            cfmm: address(0),
            amount: withdrawAmt,
            to: address(0),
            deadline: block.timestamp,
            amountsMin: new uint256[](2)
        });

        ILPZapper.LPSwapParams memory lpSwap0 = ILPZapper.LPSwapParams({
            amount: 0,
            protocolId: 0,
            path: new address[](0),
            uniV3Path: new bytes(0)
        });

        ILPZapper.LPSwapParams memory lpSwap1 = ILPZapper.LPSwapParams({
            amount: 0,
            protocolId: 0,
            path: new address[](0),
            uniV3Path: new bytes(0)
        });

        if(swapPath == 1) { // usdc
            lpSwap0.protocolId = 1;
            lpSwap0.path = new address[](2);
            lpSwap0.path[0] = _params.token0;
            lpSwap0.path[1] = _params.token1;
        } else if(swapPath == 2) { // weth
            lpSwap1.protocolId = 1;
            lpSwap1.path = new address[](2);
            lpSwap1.path[0] = _params.token1;
            lpSwap1.path[1] = _params.token0;
        } else if(swapPath == 3) { // usdc6
            lpSwap0.protocolId = 1;
            lpSwap0.path = new address[](2);
            lpSwap0.path[0] = _params.token0; // weth
            lpSwap0.path[1] = address(usdc6); // usdc6
        } else if(swapPath == 4) { // weth6
            lpSwap0.protocolId = 1;
            lpSwap0.path = new address[](3);
            lpSwap0.path[0] = _params.token0; // weth
            lpSwap0.path[1] = address(usdc6); // usdc6
            lpSwap0.path[2] = address(weth6); // weth6
        } else if(swapPath == 5) { // weth6
            lpSwap1.protocolId = 1;
            lpSwap1.path = new address[](2);
            lpSwap1.path[0] = _params.token1; // usdc
            lpSwap1.path[1] = address(weth6); // weth6
        } else if(swapPath == 6) { // usdc6
            lpSwap1.protocolId = 1;
            lpSwap1.path = new address[](3);
            lpSwap1.path[0] = _params.token1; // usdc
            lpSwap1.path[1] = _params.token0; // weth
            lpSwap1.path[2] = address(usdc6); // usdc6
        } else if(swapPath == 7) { // swap both to weth6
            lpSwap0.protocolId = 1;
            lpSwap0.path = new address[](3);
            lpSwap0.path[0] = _params.token0; // weth
            lpSwap0.path[1] = address(usdc6); // usdc6
            lpSwap0.path[2] = address(weth6); // weth6
            lpSwap1.protocolId = 1;
            lpSwap1.path = new address[](2);
            lpSwap1.path[0] = _params.token1; // usdc
            lpSwap1.path[1] = address(weth6); // weth6
        }

        vm.startPrank(user);

        GammaSwapLibrary.safeApprove(_params.lpToken, address(lpZapper), withdrawAmt);

        _params.balWETH = IERC20(_params.token0).balanceOf(user);
        _params.balUSDC = IERC20(_params.token1).balanceOf(user);
        _params.balWETH6 = IERC20(weth6).balanceOf(user);
        _params.balUSDC6 = IERC20(usdc6).balanceOf(user);

        vm.expectRevert("LP_ZAPPER: INVALID_PARAM_TO");
        isCFMMWithdrawal ? lpZapper.dsZapOutToken(params, lpSwap0, lpSwap1) : lpZapper.zapOutToken(params, lpSwap0, lpSwap1);

        params.to = user;

        vm.expectRevert("LP_ZAPPER: INVALID_PARAM_CFMM");
        isCFMMWithdrawal ? lpZapper.dsZapOutToken(params, lpSwap0, lpSwap1) : lpZapper.zapOutToken(params, lpSwap0, lpSwap1);

        params.cfmm = address(cfmm);

        if(swapPath > 0 && swapPath < 8) {
            lpSwap0.amount = type(uint256).max;
            lpSwap1.amount = type(uint256).max;

            vm.expectRevert("DeltaSwapRouter: INSUFFICIENT_OUTPUT_AMOUNT");
            isCFMMWithdrawal ? lpZapper.dsZapOutToken(params, lpSwap0, lpSwap1) : lpZapper.zapOutToken(params, lpSwap0, lpSwap1);
        }

        lpSwap0.amount = 0;
        lpSwap1.amount = 0;
        isCFMMWithdrawal ? lpZapper.dsZapOutToken(params, lpSwap0, lpSwap1) : lpZapper.zapOutToken(params, lpSwap0, lpSwap1);

        assertEq(gslpBalance - withdrawAmt, IERC20(_params.lpToken).balanceOf(user));

        if(swapPath == 0) {
            assertEq(_params.balWETH + 1e18 * uint256(percent) / 100, IERC20(_params.token0).balanceOf(user));
            assertEq(_params.balUSDC + 1e18 * uint256(percent) / 100, IERC20(_params.token1).balanceOf(user));
        } else if(swapPath == 1) { // usdc
            assertEq(_params.balWETH, IERC20(_params.token0).balanceOf(user));
            assertApproxEqRel(_params.balUSDC + 1e18 * 2 * uint256(percent) / 100, IERC20(_params.token1).balanceOf(user), 1e16);
        } else if(swapPath == 2) { // weth
            assertApproxEqRel(_params.balWETH + 1e18 * 2 * uint256(percent) / 100, IERC20(_params.token0).balanceOf(user), 1e16);
            assertEq(_params.balUSDC, IERC20(_params.token1).balanceOf(user));
        } else if(swapPath == 3) { // usdc6
            assertEq(_params.balWETH, IERC20(_params.token0).balanceOf(user));
            assertEq(_params.balUSDC + 1e18 * uint256(percent) / 100, IERC20(_params.token1).balanceOf(user));
            assertApproxEqRel(_params.balUSDC6 + 1e6 * uint256(percent) / 100, IERC20(usdc6).balanceOf(user), 1e16);
        } else if(swapPath == 4) { // weth6
            assertEq(_params.balWETH, IERC20(_params.token0).balanceOf(user));
            assertEq(_params.balUSDC + 1e18 * uint256(percent) / 100, IERC20(_params.token1).balanceOf(user));
            assertApproxEqRel(_params.balWETH6 + 1e6 * uint256(percent) / 100, IERC20(weth6).balanceOf(user), 16e15);
        } else if(swapPath == 5) { // weth6
            assertEq(_params.balWETH + 1e18 * uint256(percent) / 100, IERC20(_params.token0).balanceOf(user));
            assertEq(_params.balUSDC, IERC20(_params.token1).balanceOf(user));
            assertApproxEqRel(_params.balWETH6 + 1e6 * uint256(percent) / 100, IERC20(weth6).balanceOf(user), 16e15);
        } else if(swapPath == 6) { // usdc6
            assertEq(_params.balWETH + 1e18 * uint256(percent) / 100, IERC20(_params.token0).balanceOf(user));
            assertEq(_params.balUSDC, IERC20(_params.token1).balanceOf(user));
            assertApproxEqRel(_params.balUSDC6 + 1e6 * uint256(percent) / 100, IERC20(usdc6).balanceOf(user), 16e15);
        } else if(swapPath == 7) { // weth6
            assertEq(_params.balUSDC, IERC20(_params.token0).balanceOf(user));
            assertEq(_params.balUSDC, IERC20(_params.token1).balanceOf(user));
            assertApproxEqRel(_params.balWETH6 + 1e6 * 2 * uint256(percent) / 100, IERC20(weth6).balanceOf(user), 3e16);
        }
        vm.stopPrank();
    }

    function testZapIn(uint16 fundAmt, uint8 useToken) public {
        fundAmt = fundAmt < 100 ? 100 : fundAmt;

        uint256[] memory amountsMin = new uint256[](2);
        IPositionManager.DepositReservesParams memory params = IPositionManager.DepositReservesParams({
            protocolId: 1,
            cfmm: address(0),
            to: address(0),
            deadline: block.timestamp,
            amountsDesired: new uint256[](0),
            amountsMin: amountsMin
        });

        ILPZapper.LPSwapParams memory lpSwap = ILPZapper.LPSwapParams({
            amount: 0,
            protocolId: 0,
            path: new address[](0),
            uniV3Path: new bytes(0)
        });

        ILPZapper.FundSwapParams memory fundSwap = ILPZapper.FundSwapParams({
            protocolId: 1,
            path: new address[](0),
            uniV3Path: new bytes(0)
        });

        address tokenIn = address(weth);
        uint256 fundAmount = uint256(fundAmt) * 1e14;
        uint256 expFundAmount = fundAmount;

        if(useToken > 1 && useToken < 3) {
            tokenIn = address(usdc);
        } else if(useToken == 3) { // usdc6
            tokenIn = address(usdc6);
            fundAmount = fundAmount / 1e12;
            fundSwap.path = new address[](2);
            fundSwap.path[0] = address(usdc6);
            fundSwap.path[1] = address(weth);
        } else if(useToken == 4) { // weth6
            tokenIn = address(weth6);
            fundAmount = fundAmount / 1e12;
            fundSwap.path = new address[](2);
            fundSwap.path[0] = address(weth6);
            fundSwap.path[1] = address(usdc);
        } else if(useToken == 5) { // weth6
            tokenIn = address(usdc6);
            fundAmount = fundAmount / 1e12;
            fundSwap.path = new address[](3);
            fundSwap.path[0] = address(usdc6);
            fundSwap.path[1] = address(weth6);
            fundSwap.path[2] = address(usdc);
        } else if(useToken == 6) { // weth6
            tokenIn = address(weth6);
            fundAmount = fundAmount / 1e12;
            fundSwap.path = new address[](3);
            fundSwap.path[0] = address(weth6);
            fundSwap.path[1] = address(usdc6);
            fundSwap.path[2] = address(weth);
        }

        IERC20(tokenIn).approve(address(lpZapper), fundAmount);

        uint256 totalSupply = pool.totalSupply();
        uint256 prevGSLPBalance = pool.balanceOf(user);

        vm.expectRevert("LP_ZAPPER: INVALID_FUND_AMOUNT");
        lpZapper.zapInToken(tokenIn, 1000, params, lpSwap, fundSwap);

        vm.expectRevert("LP_ZAPPER: ZERO_ADDRESS");
        lpZapper.zapInToken(address(0), fundAmount, params, lpSwap, fundSwap);

        vm.expectRevert("LP_ZAPPER: INVALID_PARAM_TO");
        lpZapper.zapInToken(tokenIn, fundAmount, params, lpSwap, fundSwap);

        params.to = user;

        vm.expectRevert("LP_ZAPPER: INVALID_PARAM_CFMM");
        lpZapper.zapInToken(tokenIn, fundAmount, params, lpSwap, fundSwap);

        params.cfmm = address(cfmm);

        lpZapper.zapInToken(tokenIn, fundAmount, params, lpSwap, fundSwap);

        assertGt(pool.totalSupply(), totalSupply);
        assertGt(pool.balanceOf(user), prevGSLPBalance);

        IGammaPool.PoolData memory poolData = pool.getPoolData();
        uint256 userLPBalance = pool.balanceOf(user) * poolData.LP_TOKEN_BALANCE / pool.totalSupply();
        (uint256 reserve0, uint256 reserve1,) = IDeltaSwapPair(cfmm).getReserves();
        totalSupply = IERC20(cfmm).totalSupply();

        assertApproxEqRel(expFundAmount / 2, userLPBalance * reserve0 / totalSupply, 15e16);
        assertApproxEqRel(expFundAmount / 2, userLPBalance * reserve1 / totalSupply, 15e16);
    }

    function testZapInErrors() public {
        uint256[] memory amountsMin = new uint256[](2);
        IPositionManager.DepositReservesParams memory params = IPositionManager.DepositReservesParams({
            protocolId: 1,
            cfmm: address(cfmmW9),
            to: user,
            deadline: block.timestamp,
            amountsDesired: new uint256[](0),
            amountsMin: amountsMin
        });

        ILPZapper.LPSwapParams memory lpSwap = ILPZapper.LPSwapParams({
            amount: 0,
            protocolId: 0,
            path: new address[](0),
            uniV3Path: new bytes(0)
        });

        ILPZapper.FundSwapParams memory fundSwap = ILPZapper.FundSwapParams({
            protocolId: 1,
            path: new address[](0),
            uniV3Path: new bytes(0)
        });

        address tokenIn = address(weth);
        uint256 fundAmount = 1 * 1e18;

        vm.expectRevert("LP_ZAPPER: INVALID_FUND_AMOUNT");
        lpZapper.zapIn(tokenIn, 1000, params, lpSwap, fundSwap);

        vm.expectRevert("LP_ZAPPER: NO_FUND_SWAP_PATH");
        lpZapper.zapIn(tokenIn, fundAmount, params, lpSwap, fundSwap);

        GammaSwapLibrary.safeTransfer(tokenIn, address(lpZapper), fundAmount);

        fundSwap.path = new address[](2);
        fundSwap.path[0] = address(weth);
        fundSwap.path[1] = address(usdc6);

        vm.expectRevert("LP_ZAPPER: INVALID_TOKEN_OUT");
        lpZapper.zapIn(tokenIn, fundAmount, params, lpSwap, fundSwap);

        params.cfmm = address(cfmm);
        fundSwap.path = new address[](0);
        lpSwap.amount = 1001;
        lpSwap.path = new address[](2);
        lpSwap.path[0] = address(weth);
        lpSwap.path[1] = address(usdc6);

        vm.expectRevert("LP_ZAPPER: INVALID_TOKEN_OUT");
        lpZapper.zapIn(tokenIn, fundAmount, params, lpSwap, fundSwap);
    }
}
