// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IPyth.sol";
import "./IAave.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IETHLockerNFT {
    function mint(address to, uint256 tokenId) external;
}

contract ETHLocker is Ownable {
    IPyth public pyth;
    IERC721 public nft;
    IAavePool public aavePool;

    mapping(address => bytes32) public tokenToPriceFeed;
    mapping(address => address) public tokenToAToken;
    mapping(address => uint256) public totalShares;
    mapping(address => uint256) public totalaTokenShares;

    struct Lock {
        address owner;
        address token;
        uint256 shares; 
        uint256 unlockTimestamp;
        uint256 targetPrice;
        bytes32 priceFeedId;
        bool withdrawn;
    }

    mapping(uint256 => Lock) public locks;
    uint256 public lockIdCounter;

    event Deposited(uint256 indexed lockId, address indexed owner, address token, uint256 amount, uint256 shares);
    event Withdrawn(uint256 indexed lockId, address indexed owner, uint256 amount, uint256 shares);
    event TokenSupportChanged(address indexed token, bytes32 indexed priceFeedId, bool isSupported);
    event ATokenSet(address indexed token, address indexed aToken);

    constructor(
        address _pythAddress,
        address _nftAddress,
        address _aavePoolAddress
    ) Ownable(msg.sender) {
        pyth = IPyth(_pythAddress);
        nft = IERC721(_nftAddress);
        aavePool = IAavePool(_aavePoolAddress);
    }

    function setTokenSupport(address _token, bytes32 _priceFeedId, address _aToken) external onlyOwner {
        require(_token != address(0) && _aToken != address(0), "Invalid address");
        require(_priceFeedId != bytes32(0), "Invalid price feed ID");
        tokenToPriceFeed[_token] = _priceFeedId;
        tokenToAToken[_token] = _aToken;
        emit TokenSupportChanged(_token, _priceFeedId, true);
        emit ATokenSet(_token, _aToken);
    }

    function removeTokenSupport(address _token) external onlyOwner {
        bytes32 priceFeedId = tokenToPriceFeed[_token];
        require(priceFeedId != bytes32(0), "Token not supported");
        delete tokenToPriceFeed[_token];
        delete tokenToAToken[_token];
        emit TokenSupportChanged(_token, priceFeedId, false);
    }

    function deposit(address _token, uint256 _amount, uint256 timestamp, uint256 _targetPrice) external {  
        if(timestamp <= block.timestamp) {
            revert("Invalid Timestamp");
        }
        bytes32 priceFeedId = tokenToPriceFeed[_token];
        address aToken = tokenToAToken[_token];
        require(priceFeedId != bytes32(0), "Token is not supported");
        require(_amount > 0, "Amount must be greater than 0");

        uint256 poolTotalShares = totalShares[_token];
        uint256 sharesToMint;

        uint256 totalAssets = totalaTokenShares[aToken];

        if (poolTotalShares == 0 || totalAssets == 0) {
            sharesToMint = _amount;
        } else {
            sharesToMint = (_amount * poolTotalShares) / totalAssets;
        }

        require(sharesToMint > 0, "Shares to mint must be greater than zero");

        IERC20(_token).transferFrom(msg.sender, address(this), _amount);
        totalShares[_token] += sharesToMint;
        IERC20(_token).approve(address(aavePool), _amount);
        aavePool.supply(_token, _amount, address(this), 0);

        totalaTokenShares[aToken] += _amount;

        lockIdCounter++;
        uint256 lockId = lockIdCounter;

        locks[lockId] = Lock({
            owner: msg.sender,
            token: _token,
            shares: sharesToMint,
            unlockTimestamp: timestamp,
            targetPrice: _targetPrice,
            priceFeedId: priceFeedId,
            withdrawn: false
        });

        IETHLockerNFT(address(nft)).mint(msg.sender, lockId);
        emit Deposited(lockId, msg.sender, _token, _amount, sharesToMint);
    }

    function withdraw(uint256 _lockId) external {
        Lock storage userLock = locks[_lockId];
        require(userLock.owner != address(0), "Lock does not exist");
        require(!userLock.withdrawn, "Lock has already been withdrawn");
        require(nft.ownerOf(_lockId) == msg.sender, "You are not the owner of this lock's NFT");

        bool timeMet = block.timestamp >= userLock.unlockTimestamp;
        IPyth.Price memory price = pyth.getPriceUnsafe(userLock.priceFeedId);
        int256 scaledTargetPrice = int256(userLock.targetPrice) * int256(10 ** uint256(-int256(price.expo)));
        bool priceMet = price.price >= scaledTargetPrice;

        require(timeMet || priceMet, "Withdrawal conditions not met");

        address aToken = tokenToAToken[userLock.token];
        uint256 poolTotalAssets = totalaTokenShares[aToken];
        uint256 poolTotalShares = totalShares[userLock.token];
        uint256 amountToWithdraw = (userLock.shares * poolTotalAssets) / poolTotalShares;

        userLock.withdrawn = true;
        totalShares[userLock.token] -= userLock.shares;

        totalaTokenShares[aToken] -= amountToWithdraw;
        uint256 withdrawnAmount = aavePool.withdraw(userLock.token, amountToWithdraw, msg.sender);
        emit Withdrawn(_lockId, msg.sender, withdrawnAmount, userLock.shares);
    }

    function getLockDetails(uint256 _lockId) external view returns (Lock memory) {
        return locks[_lockId];
    }
}
