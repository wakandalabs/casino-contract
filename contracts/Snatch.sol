//SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./interfaces/ISnatch.sol";
import "./lib/RrpRequesterV0Upgradeable.sol";

contract Snatch is Initializable, RrpRequesterV0Upgradeable, OwnableUpgradeable, UUPSUpgradeable, ISnatch {
    using Counters for Counters.Counter;

    event RequestedUint256(uint256 indexed poolId, bytes32 indexed requestId);
    event ReceivedUint256(uint256 indexed poolId, bytes32 indexed requestId, uint256 response);
    event RequestedUint256Array(uint256 indexed poolId, bytes32 indexed requestId);
    event ReceivedUint256Array(uint256 indexed poolId, bytes32 indexed requestId, uint256[] response);

    address public airnode;
    bytes32 public endpointIdUint256;
    bytes32 public endpointIdUint256Array;
    address public sponsorWallet;

    // poolId => poolConfig
    mapping(uint256 => PoolConfig) private poolConfigMap;
    // address => poolId => rp
    mapping(address => mapping(uint256 => uint256)) private rpMap;
    // requestId => DrawRequest
    mapping(bytes32 => DrawRequest) private drawRequestMap;

    Counters.Counter private poolIdCounter;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _airnodeRrp) initializer public {
        __RrpRequesterV0_init(_airnodeRrp);
        __Ownable_init();
        __UUPSUpgradeable_init();
    }

    /// @notice Sets parameters used in requesting QRNG services
    /// @param _airnode Airnode address
    /// @param _endpointIdUint256 Endpoint ID used to request a `uint256`
    /// @param _endpointIdUint256Array Endpoint ID used to request a `uint256[]`
    /// @param _sponsorWallet Sponsor wallet address
    function setRequestParameters(
        address _airnode,
        bytes32 _endpointIdUint256,
        bytes32 _endpointIdUint256Array,
        address _sponsorWallet
    ) onlyOwner external {
        airnode = _airnode;
        endpointIdUint256 = _endpointIdUint256;
        endpointIdUint256Array = _endpointIdUint256Array;
        sponsorWallet = _sponsorWallet;
    }

    /// @notice Creates a new pool
    function createPool(PoolConfig memory config) onlyOwner external returns (uint256 poolId) {
        poolId = poolIdCounter.current();
        poolConfigMap[poolId] = config;
        poolIdCounter.increment();
    }

    // @notice Update exist pool's config
    function setPoolConfig(uint256 _poolId, PoolConfig memory config) onlyOwner external {
        require(_poolId < poolIdCounter.current(), "Pool does not exist");
        poolConfigMap[_poolId] = config;
    }

    function nextPoolId() external view returns (uint256 poolId) {
        poolId = poolIdCounter.current();
    }

    function draw(uint256 _poolId) payable external {
        require(_poolId < poolIdCounter.current(), "Pool does not exist");
        PoolConfig memory config = poolConfigMap[_poolId];

        if (config.paymentToken == address(0)) {
            require(msg.value == config.singleDrawPrice, "Invalid value");
        } else {
            require(ERC20(config.paymentToken).transferFrom(msg.sender, address(this), config.singleDrawPrice), "Transfer failed");
        }

        bytes32 requestId = airnodeRrp.makeFullRequest(
            airnode,
            endpointIdUint256,
            address(this),
            sponsorWallet,
            address(this),
            this.fulfillUint256.selector,
            ""
        );
        drawRequestMap[requestId] = DrawRequest(msg.sender, _poolId, true);
        emit RequestedUint256(_poolId, requestId);
    }

    function batchDraw(uint256 _poolId) payable external {
        require(_poolId < poolIdCounter.current(), "Pool does not exist");
        PoolConfig memory config = poolConfigMap[_poolId];

        if (config.paymentToken == address(0)) {
            require(msg.value >= config.batchDrawPrice, "Invalid value");
        } else {
            require(ERC20(config.paymentToken).transferFrom(msg.sender, address(this), config.batchDrawPrice), "Transfer failed");
        }

        bytes32 requestId = airnodeRrp.makeFullRequest(
            airnode,
            endpointIdUint256Array,
            address(this),
            sponsorWallet,
            address(this),
            this.fulfillUint256Array.selector,
            abi.encode(bytes32("1u"), bytes32("size"), config.batchDrawSize)
        );
        drawRequestMap[requestId] = DrawRequest(msg.sender, _poolId, true);
        emit RequestedUint256Array(_poolId, requestId);
    }

    function _calculateP(uint256 _poolId, uint256 _rp) internal view returns (uint256) {
        PoolConfig memory config = poolConfigMap[_poolId];
        if (_rp >= config.rarePrizeMaxRP) {
            return 1 ether;
        }

        return config.rarePrizeInitRate + config.rarePrizeRateD * _rp;
    }

    /// @notice Called by the Airnode through the AirnodeRrp contract to
    /// fulfill the request
    /// @dev Note the `onlyAirnodeRrp` modifier. You should only accept RRP
    /// fulfillments from this protocol contract. Also note that only
    /// fulfillments for the requests made by this contract are accepted, and
    /// a request cannot be responded to multiple times.
    /// @param requestId Request IDw
    /// @param data ABI-encoded response
    function fulfillUint256(bytes32 requestId, bytes calldata data)
    external
    onlyAirnodeRrp
    {
        uint256 qrngUint256 = abi.decode(data, (uint256));
        uint256 poolId = drawRequestMap[requestId].poolId;
        emit ReceivedUint256(poolId, requestId, qrngUint256);
        _settle(requestId, qrngUint256);
        delete drawRequestMap[requestId];
    }

    /// @notice Called by the Airnode through the AirnodeRrp contract to
    /// fulfill the request
    /// @param requestId Request ID
    /// @param data ABI-encoded response
    function fulfillUint256Array(bytes32 requestId, bytes calldata data)
    external
    onlyAirnodeRrp
    {
        require(
            drawRequestMap[requestId].isWaitingFulfill,
            "Request ID not known"
        );
        uint256[] memory qrngUint256Array = abi.decode(data, (uint256[]));
        uint256 poolId = drawRequestMap[requestId].poolId;
        emit ReceivedUint256Array(poolId, requestId, qrngUint256Array);

        for (uint256 j = 0; j < qrngUint256Array.length; j++) {
            uint256 qrngUint256 = qrngUint256Array[j];
            _settle(requestId, qrngUint256);
        }
        delete drawRequestMap[requestId];
    }

    function _settle(bytes32 requestId, uint256 qrngUint256)
    internal
    {
        require(
            drawRequestMap[requestId].isWaitingFulfill,
            "Request ID not known"
        );
        address requester = drawRequestMap[requestId].requester;
        qrngUint256 = qrngUint256 % 1 ether;
        uint256 poolId = drawRequestMap[requestId].poolId;
        uint256 p = _calculateP(poolId, rpMap[requester][poolId]);
        PoolConfig memory config = poolConfigMap[poolId];
        if (qrngUint256 <= p) {
            if (_safeBalanceOf(config.rarePrizeToken, address(this)) >= config.rarePrizeValue) {
                delete rpMap[requester][poolId];
                _safeTransfer(config.rarePrizeToken, requester, config.rarePrizeValue);
            } else {
                _safeTransfer(config.paymentToken, requester, config.singleDrawPrice);
            }
        } else {
            uint256 start = 0;
            rpMap[requester][poolId] += 1;
            for (uint256 i = 0; i < config.normalPrizesRate.length; i++) {
                start += config.normalPrizesRate[i];
                if (qrngUint256 <= start) {
                    if (_safeBalanceOf(config.normalPrizesToken[i], address(this)) >= config.normalPrizesValue[i]) {
                        _safeTransfer(config.normalPrizesToken[i], requester, config.normalPrizesValue[i]);
                    } else {
                        _safeTransfer(config.paymentToken, requester, config.singleDrawPrice);
                    }
                    break;
                }
            }
        }
    }

    function _safeBalanceOf(address _token, address _account) internal view returns (uint256) {
        if (_token == address(0)) {
            return _account.balance;
        } else {
            return ERC20(_token).balanceOf(_account);
        }
    }

    function _safeTransfer(address token, address to, uint256 value) internal {
        if (token == address(0)) {
            payable(to).transfer(value);
        } else {
            ERC20(token).transfer(to, value);
        }
    }

    function withdraw(address token, uint256 amount) onlyOwner external {
        if (token == address(0)) {
            require(amount <= address(this).balance, "Not enough balance");
            payable(msg.sender).transfer(amount);
        } else {
            require(amount <= ERC20(token).balanceOf(address(this)), "Not enough balance");
            ERC20(token).transfer(msg.sender, amount);
        }
    }

    function rpOf(address _user, uint256 _poolId) external view returns (uint256) {
        require(_poolId < poolIdCounter.current(), "Pool does not exist");
        return rpMap[_user][_poolId];
    }

    function poolConfigOf(uint256 _poolId) external view returns (PoolConfig memory) {
        require(_poolId < poolIdCounter.current(), "Pool does not exist");
        return poolConfigMap[_poolId];
    }

    function drawRequestOf(bytes32 _requestId) external view returns (DrawRequest memory) {
        return drawRequestMap[_requestId];
    }

    function _authorizeUpgrade(address newImplementation)
    internal
    onlyOwner
    override
    {}
}