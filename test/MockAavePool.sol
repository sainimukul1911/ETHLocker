// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import "../contracts/ETHLocker.sol";
import "../contracts/ETHLockerNFT.sol";
import "../contracts/IAave.sol";
import "../contracts/IPyth.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {MockERC20} from "./ETHLocker.t.sol";

contract MockAavePool is IAavePool {
    MockERC20 public mockaToken;

    constructor(address _mockaToken) {
        mockaToken = MockERC20(_mockaToken);
    }
    
    function supply(address asset, uint256 amount, address onBehalfOf, uint16) external {
        IERC20(asset).transferFrom(onBehalfOf, address(this), amount);
        IERC20(mockaToken).transfer(msg.sender, amount);
    }

    function withdraw(address asset, uint256 amount, address to) external returns (uint256) {
        IERC20(mockaToken).transferFrom(msg.sender, address(this), amount);
        IERC20(asset).transfer(to, amount);
        return amount;
    }
}