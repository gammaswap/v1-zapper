// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../LPZapper.sol";

contract TestLPZapper is LPZapper {

    constructor(address _WETH, address _factory, address _dsFactory, address _positionManager, address _mathLib,
        address _uniV2Router, address _sushiRouter, address _dsRouter, address _uniV3Router)
        LPZapper(_WETH, _factory, _dsFactory, _positionManager, _mathLib, _uniV2Router, _sushiRouter, _dsRouter, _uniV3Router) {
    }

    function getTokenOut(bytes memory path) public view returns(address tokenOut) {
        return _getTokenOut(path);
    }
}
