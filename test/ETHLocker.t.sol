// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import "../contracts/ETHLocker.sol";
import "../contracts/ETHLockerNFT.sol";
import "../contracts/IAave.sol";
import "../contracts/IPyth.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {MockAavePool} from "./MockAavePool.sol";

contract MockERC20 is ERC20 {
    constructor() ERC20("Mock Token", "MTK") {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

contract ETHLockerTest is Test {
    ETHLocker ethLocker;
    ETHLockerNFT ethLockerNFT;
    IPyth mockPyth;
    MockAavePool mockAavePool;
    MockERC20 mockToken;
    MockERC20 public mockaToken;
    MockERC20 newToken;
    MockERC20 newAToken;

    address owner = address(0x1);
    address user = address(0x2);

    bytes32 constant PRICE_FEED_ID = 0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace;

    function setUp() public {
        vm.startPrank(owner);
        ethLockerNFT = new ETHLockerNFT();
        mockPyth = new MockPyth();
        mockToken = new MockERC20();
        mockaToken = new MockERC20();
        mockAavePool = new MockAavePool(address(mockaToken));
        newToken = new MockERC20();
        newAToken = new MockERC20();

        ethLocker = new ETHLocker(address(mockPyth), address(ethLockerNFT), address(mockAavePool));
        ethLockerNFT.transferOwnership(address(ethLocker));

        ethLocker.setTokenSupport(address(mockToken), PRICE_FEED_ID, address(mockaToken));
        vm.stopPrank();

        mockToken.mint(user, 1_000_000e18);
    }

    function test_SetTokenSupport() public {
        vm.startPrank(owner);
        bytes32 newPriceFeedId = keccak256("new price feed");
        ethLocker.setTokenSupport(address(newToken), newPriceFeedId, address(newAToken));

        bytes32 priceFeedId = ethLocker.tokenToPriceFeed(address(newToken));
        address aToken = ethLocker.tokenToAToken(address(newToken));

        assertEq(priceFeedId, newPriceFeedId);
        assertEq(aToken, address(newAToken));
        vm.stopPrank();
    }

    function test_RevertWhen_SetTokenSupportByNonOwner() public {
        vm.startPrank(user);
        bytes32 newPriceFeedId = keccak256("new price feed");

        vm.expectRevert();
        ethLocker.setTokenSupport(address(newToken), newPriceFeedId, address(newAToken));
        vm.stopPrank();
    }

    function test_RemoveTokenSupport() public {
        vm.startPrank(owner);
        ethLocker.removeTokenSupport(address(mockToken));

        bytes32 priceFeedId = ethLocker.tokenToPriceFeed(address(mockToken));
        address aToken = ethLocker.tokenToAToken(address(mockToken));

        assertEq(priceFeedId, bytes32(0));
        assertEq(aToken, address(0));
        vm.stopPrank();
    }

    function test_RevertWhen_RemoveTokenSupportByNonOwner() public {
        vm.startPrank(user);
        vm.expectRevert();
        ethLocker.removeTokenSupport(address(mockToken)); 
        vm.stopPrank();
    }

    function test_RevertWhen_DepositUnsupportedToken() public {
        vm.startPrank(user);
        uint256 amount = 1e18;
        uint256 unlockTimestamp = block.timestamp + 1 days;
        uint256 targetPrice = 2000e18;

        vm.expectRevert("Token is not supported");
        ethLocker.deposit(address(newToken), amount, unlockTimestamp, targetPrice);
        vm.stopPrank();
    }

    function test_RevertWhen_DepositWithInvalidTimestamp() public {
        vm.startPrank(user);
        uint256 amount = 1e18;
        uint256 unlockTimestamp = block.timestamp - 1;
        uint256 targetPrice = 2000e18;

        vm.expectRevert("Invalid Timestamp");
        ethLocker.deposit(address(mockToken), amount, unlockTimestamp, targetPrice);
        vm.stopPrank();
    }

    function test_simpleDepositAndWithdraw() public {
        vm.startPrank(user);

        uint256 amount = 1e18;
        uint256 unlockTimestamp = block.timestamp + 1 days;
        uint256 targetPrice = 2000e18;

        deal(address(mockToken), user, 1_000_000e18);
        deal(address(mockaToken), address(mockAavePool), amount);
        mockToken.approve(address(ethLocker), amount);
        ethLocker.deposit(address(mockToken), amount, unlockTimestamp, targetPrice);

        assertEq(ethLockerNFT.ownerOf(1), user, "NFT not minted to user");
        assertEq(mockToken.balanceOf(user), 1_000_000e18 - amount, "User balance after deposit is incorrect");

        vm.warp(unlockTimestamp);
        vm.stopPrank();

        vm.prank(address(ethLocker));
        IERC20(mockaToken).approve(address(mockAavePool), amount);
        vm.prank(user);
        ethLocker.withdraw(1);

        assertEq(mockToken.balanceOf(user), 1_000_000e18, "User balance after withdraw is incorrect");
    }

    function test_Withdraw_RevertWhen_ConditionsNotMet() public {
        vm.startPrank(user);

        uint256 amount = 1e18;
        uint256 unlockTimestamp = block.timestamp + 1 days;
        uint256 targetPrice = 3000e18; // Higher than current price

        deal(address(mockToken), user, amount);
        deal(address(mockaToken), address(mockAavePool), amount);
        mockToken.approve(address(ethLocker), amount);
        ethLocker.deposit(address(mockToken), amount, unlockTimestamp, targetPrice);

        vm.expectRevert();
        ethLocker.withdraw(1);
        vm.stopPrank();
    }
}

contract MockPyth is IPyth {
    function getPrice(bytes32) external view returns (Price memory) {
        return Price(2000e8, 1e8, -8, uint64(block.timestamp));
    }

    function getPriceUnsafe(bytes32) external view returns (Price memory) {
        return Price(2000e8, 1e8, -8, uint64(block.timestamp));
    }
}