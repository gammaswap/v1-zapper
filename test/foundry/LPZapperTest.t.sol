// SPDX-License-Identifier: GPL-v3
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@gammaswap/v1-core/contracts/libraries/GSMath.sol";
import "./fixtures/CPMMGammaSwapSetup.sol";
import "../../contracts/LPZapper.sol";

contract LPZapperTest is CPMMGammaSwapSetup {

    ILPZapper lpZapper;
    address user;

    function setUp() public {
        super.initCPMMGammaSwap(true);
        user = vm.addr(3);

        lpZapper = new LPZapper(address(factory), address(posMgr), address(mathLib), address(uniRouter), address(0), address(uniRouter), address(0));
        deal(address(weth), user, 1000_000*1e18);
        deal(address(usdc), user, 1000_000*1e18);

        depositLiquidityInCFMM(addr2, 100e18, 100e18);
        depositLiquidityInPool(addr2);

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

    function testZapOut(uint8 swapPath, uint8 percent) public {
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

        address token0 = ICPMM(cfmm).token0();
        address token1 = ICPMM(cfmm).token1();

        IERC20(token0).approve(address(posMgr), 1e18);
        IERC20(token1).approve(address(posMgr), 1e18);

        posMgr.depositReserves(depositParams);

        uint256 gslpBalance = pool.balanceOf(user);

        uint256 withdrawAmt = gslpBalance * percent / 100;

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

        if(swapPath == 1) { // usdc
            lpSwap0.protocolId = 1;
            lpSwap0.path = new address[](2);
            lpSwap0.path[0] = token0;
            lpSwap0.path[1] = token1;
        } else if(swapPath == 2) { // weth
            lpSwap1.protocolId = 1;
            lpSwap1.path = new address[](2);
            lpSwap1.path[0] = token1;
            lpSwap1.path[1] = token0;
        } else if(swapPath == 3) { // usdc6
            lpSwap0.protocolId = 1;
            lpSwap0.path = new address[](2);
            lpSwap0.path[0] = token0; // weth
            lpSwap0.path[1] = address(usdc6); // usdc6
        } else if(swapPath == 4) { // weth6
            lpSwap0.protocolId = 1;
            lpSwap0.path = new address[](3);
            lpSwap0.path[0] = token0; // weth
            lpSwap0.path[1] = address(usdc6); // usdc6
            lpSwap0.path[2] = address(weth6); // weth6
        } else if(swapPath == 5) { // weth6
            lpSwap1.protocolId = 1;
            lpSwap1.path = new address[](2);
            lpSwap1.path[0] = token1; // usdc
            lpSwap1.path[1] = address(weth6); // weth6
        } else if(swapPath == 6) { // usdc6
            lpSwap1.protocolId = 1;
            lpSwap1.path = new address[](3);
            lpSwap1.path[0] = token1; // usdc
            lpSwap1.path[1] = token0; // weth
            lpSwap1.path[2] = address(usdc6); // usdc6
        } else if(swapPath == 7) { // swap both to weth6
            lpSwap0.protocolId = 1;
            lpSwap0.path = new address[](3);
            lpSwap0.path[0] = token0; // weth
            lpSwap0.path[1] = address(usdc6); // usdc6
            lpSwap0.path[2] = address(weth6); // weth6
            lpSwap1.protocolId = 1;
            lpSwap1.path = new address[](2);
            lpSwap1.path[0] = token1; // usdc
            lpSwap1.path[1] = address(weth6); // weth6
        }

        vm.startPrank(user);

        GammaSwapLibrary.safeApprove(address(pool), address(lpZapper), withdrawAmt);

        uint256 balWETH = IERC20(token0).balanceOf(user);
        uint256 balUSDC = IERC20(token1).balanceOf(user);
        uint256 balWETH6 = IERC20(weth6).balanceOf(user);
        uint256 balUSDC6 = IERC20(usdc6).balanceOf(user);
        console.log(balWETH);
        console.log(balUSDC);
        console.log(balWETH6);
        console.log(balUSDC6);
        console.log(gslpBalance);

        lpZapper.zapOut(params, lpSwap0, lpSwap1);

        assertEq(gslpBalance - withdrawAmt, pool.balanceOf(user));

        if(swapPath == 0) {
            assertEq(balWETH + 1e18 * uint256(percent) / 100, IERC20(token0).balanceOf(user));
            assertEq(balUSDC + 1e18 * uint256(percent) / 100, IERC20(token1).balanceOf(user));
        } else if(swapPath == 1) { // usdc
            assertEq(balWETH, IERC20(token0).balanceOf(user));
            assertApproxEqRel(balUSDC + 1e18 * 2 * uint256(percent) / 100, IERC20(token1).balanceOf(user), 1e16);
        } else if(swapPath == 2) { // weth
            assertApproxEqRel(balWETH + 1e18 * 2 * uint256(percent) / 100, IERC20(token0).balanceOf(user), 1e16);
            assertEq(balUSDC, IERC20(token1).balanceOf(user));
        } else if(swapPath == 3) { // usdc6
            assertEq(balWETH, IERC20(token0).balanceOf(user));
            assertEq(balUSDC + 1e18 * uint256(percent) / 100, IERC20(token1).balanceOf(user));
            assertApproxEqRel(balUSDC6 + 1e6 * uint256(percent) / 100, IERC20(usdc6).balanceOf(user), 1e16);
        } else if(swapPath == 4) { // weth6
            assertEq(balWETH, IERC20(token0).balanceOf(user));
            assertEq(balUSDC + 1e18 * uint256(percent) / 100, IERC20(token1).balanceOf(user));
            assertApproxEqRel(balWETH6 + 1e6 * uint256(percent) / 100, IERC20(weth6).balanceOf(user), 16e15);
        } else if(swapPath == 5) { // weth6
            assertEq(balWETH + 1e18 * uint256(percent) / 100, IERC20(token0).balanceOf(user));
            assertEq(balUSDC, IERC20(token1).balanceOf(user));
            assertApproxEqRel(balWETH6 + 1e6 * uint256(percent) / 100, IERC20(weth6).balanceOf(user), 16e15);
        } else if(swapPath == 6) { // usdc6
            assertEq(balWETH + 1e18 * uint256(percent) / 100, IERC20(token0).balanceOf(user));
            assertEq(balUSDC, IERC20(token1).balanceOf(user));
            assertApproxEqRel(balUSDC6 + 1e6 * uint256(percent) / 100, IERC20(usdc6).balanceOf(user), 16e15);
        } else if(swapPath == 7) { // weth6
            assertEq(balUSDC, IERC20(token0).balanceOf(user));
            assertEq(balUSDC, IERC20(token1).balanceOf(user));
            assertApproxEqRel(balWETH6 + 1e6 * 2 * uint256(percent) / 100, IERC20(weth6).balanceOf(user), 3e16);
        }
        vm.stopPrank();
    }

    function testZapIn(uint16 fundAmt, uint8 useToken) public {
    //function testZapIn() public {
        //(uint16 fundAmt, uint8 useToken) = (52779, 5);
        fundAmt = fundAmt < 100 ? 100 : fundAmt;

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

        lpZapper.zapIn(tokenIn, fundAmount, params, lpSwap, fundSwap);

        assertGt(pool.totalSupply(), totalSupply);
        assertGt(pool.balanceOf(user), prevGSLPBalance);

        IGammaPool.PoolData memory poolData = pool.getPoolData();
        uint256 userLPBalance = pool.balanceOf(user) * poolData.LP_TOKEN_BALANCE / pool.totalSupply();
        (uint256 reserve0, uint256 reserve1,) = IDeltaSwapPair(cfmm).getReserves();
        totalSupply = IERC20(cfmm).totalSupply();

        assertApproxEqRel(expFundAmount / 2, userLPBalance * reserve0 / totalSupply, 15e16);
        assertApproxEqRel(expFundAmount / 2, userLPBalance * reserve1 / totalSupply, 15e16);
    }
}
