// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "@gammaswap/v1-core/contracts/libraries/GammaSwapLibrary.sol";
import "@gammaswap/v1-periphery/contracts/interfaces/external/IWETH.sol";
import "@gammaswap/v1-liquidator/contracts/test/TestERC20.sol";

contract TestWETH is TestERC20, IWETH{
    constructor(string memory name_, string memory symbol_) TestERC20(name_, symbol_) {
    }

    receive() external payable {
        deposit();
    }

    function deposit() public payable {
        uint256 amount = msg.value;
        address to = msg.sender;

        _mint(to, amount);

        emit Deposit(to, amount);
    }

    function withdraw(uint amount) public {
        address from = msg.sender;

        require(balanceOf(from) >= amount);

        _burn(from, amount);

        GammaSwapLibrary.safeTransferETH(from, amount);

        emit Withdrawal(from, amount);
    }
}
