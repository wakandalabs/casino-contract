//SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

interface IPrintingPod {
    struct DrawRequest {
        address requester;              // requester address
        bool isWaitingFulfill;          // is waiting fulfill
    }

    struct Blueprint {
        string name;                     // blueprint name
        string description;              // blueprint description
        string image;                    // blueprint image uri
    }

    struct interestDNA {
        string name;                     // blueprint name
        string description;              // blueprint description
        string image;                    // blueprint image uri
        string interest1Type;            // interest 1 type
        string interest2Type;            // interest 2 index
        string interest3Type;            // interest 3 index
        uint8 interestsSize;             // interests size
        uint8 interest1Value;            // interest 1 value
        uint8 interest2Value;            // interest 2 value
        uint8 interest3Value;            // interest 3 value
    }

    // @notice Upgrade interest by native currency
    function upgradeInterest(uint256 _tokenId) external payable;

    // @notice Get max interest points
    function getMaxInterestPoints() external returns (uint8);

    function getInterestTypes(uint256 offset, uint256 limit) external view returns (string[] memory);

    function addInterestType(string calldata _type) payable external;

    function batchAddInterestTypes(string[] calldata _types) payable external;

    function getBlueprints(uint256 offset, uint256 limit) external view returns (Blueprint[] memory);

    function addBlueprint(Blueprint memory _blueprint) external;

    function batchAddBlueprints(Blueprint[] calldata _blueprints) external;

    function draw(uint256 size) external payable;

    function withdraw(address _token, uint256 _amount) external;

    function safeMint(address to, uint256[] calldata indexes) external;

    function draftInterestDNAsOf(address _owner) external view returns (interestDNA[] memory);

    function printInterestDNAOf(uint256 _tokenId) external view returns (interestDNA memory);

    function blueprintsCounter() external view returns (uint256);

    function interestTypesCounter() external view returns (uint256);

    function setSponsorFee(uint256 _value) external;
}