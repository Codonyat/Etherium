// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title WMEGAAddresses
/// @notice Centralized WMEGA address lookup for all chains
library WMEGAAddresses {
    // MegaETH WMEGA addresses
    address public constant WMEGA_MAINNET =
        0x4eB2Bd7beE16F38B1F4a0A5796Fffd028b6040e9;
    address public constant WMEGA_TESTNET =
        0x4eB2Bd7beE16F38B1F4a0A5796Fffd028b6040e9;

    /// @dev Returns the appropriate WMEGA address for the current chain
    /// @return The WMEGA address, or address(0) for unsupported chains (local testing)
    function getWMEGAAddress() internal view returns (address) {
        uint256 chainId = block.chainid;

        // MegaETH Mainnet chain ID
        if (chainId == 4326) {
            return WMEGA_MAINNET;
        }
        // MegaETH Testnet chain ID
        else if (chainId == 6343) {
            return WMEGA_TESTNET;
        }
        // Local testing (Foundry default is 31337) or unsupported
        else {
            return address(0);
        }
    }

    /// @dev Returns the WMEGA address or reverts for unsupported chains (for deployment)
    function getWMEGAAddressStrict() internal view returns (address) {
        address wmega = getWMEGAAddress();
        require(wmega != address(0), "Not a supported chain.");
        return wmega;
    }
}
