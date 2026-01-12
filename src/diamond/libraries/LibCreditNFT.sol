// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {CreditOracle} from "../../CreditOracle.sol";

library LibCreditNFT {
    bytes32 constant CREDIT_NFT_STORAGE_POSITION = keccak256("diamond.standard.credit.nft.storage");

    struct CreditNFTStorage {
        // NFT state
        string name;
        string symbol;
        uint256 nextTokenId;

        // ERC721 mappings
        mapping(uint256 => address) owners;
        mapping(address => uint256) balances;
        mapping(uint256 => address) tokenApprovals;
        mapping(address => mapping(address => bool)) operatorApprovals;

        // Credit NFT specific
        mapping(address => uint256) userToTokenId;
        mapping(uint256 => address) tokenIdToUser;
        CreditOracle creditOracle;

        // Tier thresholds
        uint256 platinumThreshold;
        uint256 goldThreshold;
        uint256 silverThreshold;
    }

    function creditNFTStorage() internal pure returns (CreditNFTStorage storage ds) {
        bytes32 position = CREDIT_NFT_STORAGE_POSITION;
        assembly {
            ds.slot := position
        }
    }

    function initializeStorage(address _creditOracle) internal {
        CreditNFTStorage storage s = creditNFTStorage();
        s.name = "Base Credit Identity";
        s.symbol = "BCREDIT";
        s.nextTokenId = 1;
        s.creditOracle = CreditOracle(_creditOracle);
        s.platinumThreshold = 750;
        s.goldThreshold = 650;
        s.silverThreshold = 550;
    }
}
