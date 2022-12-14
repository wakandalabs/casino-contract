//SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

interface IFourDucks {
    struct PoolConfig {
        address[] players;          // players
        address[] tokens;           // payment token address
        int256[] amount;           // stake amount
    }

    struct StakeRequest {
        address poolId;              // pool Id
        bool isWaitingFulfill;       // is waiting fulfill
    }

    // 10% = 1e17
    function setPlatformFee(uint256 _value) external;

    function setSponsorFee(uint256 _value) external;

    function soloStake(address _poolId, address _token, int256 _amount) payable external;

    function pooledStake(address _poolId, address _token, int256 _amount) payable external;

    function withdraw(address _token, uint256 _amount) external;

    function poolConfigOf(address _poolId) external view returns (PoolConfig memory);
}