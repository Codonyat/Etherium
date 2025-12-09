// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.4.16 >=0.6.2 >=0.8.4 ^0.8.20 ^0.8.24;

// lib/openzeppelin-contracts/contracts/utils/Context.sol

// OpenZeppelin Contracts (last updated v5.0.1) (utils/Context.sol)

/**
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }

    function _contextSuffixLength() internal view virtual returns (uint256) {
        return 0;
    }
}

// lib/openzeppelin-contracts/contracts/utils/introspection/IERC165.sol

// OpenZeppelin Contracts (last updated v5.4.0) (utils/introspection/IERC165.sol)

/**
 * @dev Interface of the ERC-165 standard, as defined in the
 * https://eips.ethereum.org/EIPS/eip-165[ERC].
 *
 * Implementers can declare support of contract interfaces, which can then be
 * queried by others ({ERC165Checker}).
 *
 * For an implementation, see {ERC165}.
 */
interface IERC165 {
    /**
     * @dev Returns true if this contract implements the interface defined by
     * `interfaceId`. See the corresponding
     * https://eips.ethereum.org/EIPS/eip-165#how-interfaces-are-identified[ERC section]
     * to learn more about how these ids are created.
     *
     * This function call must use less than 30 000 gas.
     */
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

// lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol

// OpenZeppelin Contracts (last updated v5.4.0) (token/ERC20/IERC20.sol)

/**
 * @dev Interface of the ERC-20 standard as defined in the ERC.
 */
interface IERC20 {
    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /**
     * @dev Returns the value of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the value of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves a `value` amount of tokens from the caller's account to `to`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address to, uint256 value) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets a `value` amount of tokens as the allowance of `spender` over the
     * caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 value) external returns (bool);

    /**
     * @dev Moves a `value` amount of tokens from `from` to `to` using the
     * allowance mechanism. `value` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

// lib/openzeppelin-contracts/contracts/utils/TransientSlot.sol

// OpenZeppelin Contracts (last updated v5.3.0) (utils/TransientSlot.sol)
// This file was procedurally generated from scripts/generate/templates/TransientSlot.js.

/**
 * @dev Library for reading and writing value-types to specific transient storage slots.
 *
 * Transient slots are often used to store temporary values that are removed after the current transaction.
 * This library helps with reading and writing to such slots without the need for inline assembly.
 *
 *  * Example reading and writing values using transient storage:
 * ```solidity
 * contract Lock {
 *     using TransientSlot for *;
 *
 *     // Define the slot. Alternatively, use the SlotDerivation library to derive the slot.
 *     bytes32 internal constant _LOCK_SLOT = 0xf4678858b2b588224636b8522b729e7722d32fc491da849ed75b3fdf3c84f542;
 *
 *     modifier locked() {
 *         require(!_LOCK_SLOT.asBoolean().tload());
 *
 *         _LOCK_SLOT.asBoolean().tstore(true);
 *         _;
 *         _LOCK_SLOT.asBoolean().tstore(false);
 *     }
 * }
 * ```
 *
 * TIP: Consider using this library along with {SlotDerivation}.
 */
library TransientSlot {
    /**
     * @dev UDVT that represents a slot holding an address.
     */
    type AddressSlot is bytes32;

    /**
     * @dev Cast an arbitrary slot to a AddressSlot.
     */
    function asAddress(bytes32 slot) internal pure returns (AddressSlot) {
        return AddressSlot.wrap(slot);
    }

    /**
     * @dev UDVT that represents a slot holding a bool.
     */
    type BooleanSlot is bytes32;

    /**
     * @dev Cast an arbitrary slot to a BooleanSlot.
     */
    function asBoolean(bytes32 slot) internal pure returns (BooleanSlot) {
        return BooleanSlot.wrap(slot);
    }

    /**
     * @dev UDVT that represents a slot holding a bytes32.
     */
    type Bytes32Slot is bytes32;

    /**
     * @dev Cast an arbitrary slot to a Bytes32Slot.
     */
    function asBytes32(bytes32 slot) internal pure returns (Bytes32Slot) {
        return Bytes32Slot.wrap(slot);
    }

    /**
     * @dev UDVT that represents a slot holding a uint256.
     */
    type Uint256Slot is bytes32;

    /**
     * @dev Cast an arbitrary slot to a Uint256Slot.
     */
    function asUint256(bytes32 slot) internal pure returns (Uint256Slot) {
        return Uint256Slot.wrap(slot);
    }

    /**
     * @dev UDVT that represents a slot holding a int256.
     */
    type Int256Slot is bytes32;

    /**
     * @dev Cast an arbitrary slot to a Int256Slot.
     */
    function asInt256(bytes32 slot) internal pure returns (Int256Slot) {
        return Int256Slot.wrap(slot);
    }

    /**
     * @dev Load the value held at location `slot` in transient storage.
     */
    function tload(AddressSlot slot) internal view returns (address value) {
        assembly ("memory-safe") {
            value := tload(slot)
        }
    }

    /**
     * @dev Store `value` at location `slot` in transient storage.
     */
    function tstore(AddressSlot slot, address value) internal {
        assembly ("memory-safe") {
            tstore(slot, value)
        }
    }

    /**
     * @dev Load the value held at location `slot` in transient storage.
     */
    function tload(BooleanSlot slot) internal view returns (bool value) {
        assembly ("memory-safe") {
            value := tload(slot)
        }
    }

    /**
     * @dev Store `value` at location `slot` in transient storage.
     */
    function tstore(BooleanSlot slot, bool value) internal {
        assembly ("memory-safe") {
            tstore(slot, value)
        }
    }

    /**
     * @dev Load the value held at location `slot` in transient storage.
     */
    function tload(Bytes32Slot slot) internal view returns (bytes32 value) {
        assembly ("memory-safe") {
            value := tload(slot)
        }
    }

    /**
     * @dev Store `value` at location `slot` in transient storage.
     */
    function tstore(Bytes32Slot slot, bytes32 value) internal {
        assembly ("memory-safe") {
            tstore(slot, value)
        }
    }

    /**
     * @dev Load the value held at location `slot` in transient storage.
     */
    function tload(Uint256Slot slot) internal view returns (uint256 value) {
        assembly ("memory-safe") {
            value := tload(slot)
        }
    }

    /**
     * @dev Store `value` at location `slot` in transient storage.
     */
    function tstore(Uint256Slot slot, uint256 value) internal {
        assembly ("memory-safe") {
            tstore(slot, value)
        }
    }

    /**
     * @dev Load the value held at location `slot` in transient storage.
     */
    function tload(Int256Slot slot) internal view returns (int256 value) {
        assembly ("memory-safe") {
            value := tload(slot)
        }
    }

    /**
     * @dev Store `value` at location `slot` in transient storage.
     */
    function tstore(Int256Slot slot, int256 value) internal {
        assembly ("memory-safe") {
            tstore(slot, value)
        }
    }
}

// lib/openzeppelin-contracts/contracts/interfaces/draft-IERC6093.sol

// OpenZeppelin Contracts (last updated v5.4.0) (interfaces/draft-IERC6093.sol)

/**
 * @dev Standard ERC-20 Errors
 * Interface of the https://eips.ethereum.org/EIPS/eip-6093[ERC-6093] custom errors for ERC-20 tokens.
 */
interface IERC20Errors {
    /**
     * @dev Indicates an error related to the current `balance` of a `sender`. Used in transfers.
     * @param sender Address whose tokens are being transferred.
     * @param balance Current balance for the interacting account.
     * @param needed Minimum amount required to perform a transfer.
     */
    error ERC20InsufficientBalance(address sender, uint256 balance, uint256 needed);

    /**
     * @dev Indicates a failure with the token `sender`. Used in transfers.
     * @param sender Address whose tokens are being transferred.
     */
    error ERC20InvalidSender(address sender);

    /**
     * @dev Indicates a failure with the token `receiver`. Used in transfers.
     * @param receiver Address to which tokens are being transferred.
     */
    error ERC20InvalidReceiver(address receiver);

    /**
     * @dev Indicates a failure with the `spender`’s `allowance`. Used in transfers.
     * @param spender Address that may be allowed to operate on tokens without being their owner.
     * @param allowance Amount of tokens a `spender` is allowed to operate with.
     * @param needed Minimum amount required to perform a transfer.
     */
    error ERC20InsufficientAllowance(address spender, uint256 allowance, uint256 needed);

    /**
     * @dev Indicates a failure with the `approver` of a token to be approved. Used in approvals.
     * @param approver Address initiating an approval operation.
     */
    error ERC20InvalidApprover(address approver);

    /**
     * @dev Indicates a failure with the `spender` to be approved. Used in approvals.
     * @param spender Address that may be allowed to operate on tokens without being their owner.
     */
    error ERC20InvalidSpender(address spender);
}

/**
 * @dev Standard ERC-721 Errors
 * Interface of the https://eips.ethereum.org/EIPS/eip-6093[ERC-6093] custom errors for ERC-721 tokens.
 */
interface IERC721Errors {
    /**
     * @dev Indicates that an address can't be an owner. For example, `address(0)` is a forbidden owner in ERC-20.
     * Used in balance queries.
     * @param owner Address of the current owner of a token.
     */
    error ERC721InvalidOwner(address owner);

    /**
     * @dev Indicates a `tokenId` whose `owner` is the zero address.
     * @param tokenId Identifier number of a token.
     */
    error ERC721NonexistentToken(uint256 tokenId);

    /**
     * @dev Indicates an error related to the ownership over a particular token. Used in transfers.
     * @param sender Address whose tokens are being transferred.
     * @param tokenId Identifier number of a token.
     * @param owner Address of the current owner of a token.
     */
    error ERC721IncorrectOwner(address sender, uint256 tokenId, address owner);

    /**
     * @dev Indicates a failure with the token `sender`. Used in transfers.
     * @param sender Address whose tokens are being transferred.
     */
    error ERC721InvalidSender(address sender);

    /**
     * @dev Indicates a failure with the token `receiver`. Used in transfers.
     * @param receiver Address to which tokens are being transferred.
     */
    error ERC721InvalidReceiver(address receiver);

    /**
     * @dev Indicates a failure with the `operator`’s approval. Used in transfers.
     * @param operator Address that may be allowed to operate on tokens without being their owner.
     * @param tokenId Identifier number of a token.
     */
    error ERC721InsufficientApproval(address operator, uint256 tokenId);

    /**
     * @dev Indicates a failure with the `approver` of a token to be approved. Used in approvals.
     * @param approver Address initiating an approval operation.
     */
    error ERC721InvalidApprover(address approver);

    /**
     * @dev Indicates a failure with the `operator` to be approved. Used in approvals.
     * @param operator Address that may be allowed to operate on tokens without being their owner.
     */
    error ERC721InvalidOperator(address operator);
}

/**
 * @dev Standard ERC-1155 Errors
 * Interface of the https://eips.ethereum.org/EIPS/eip-6093[ERC-6093] custom errors for ERC-1155 tokens.
 */
interface IERC1155Errors {
    /**
     * @dev Indicates an error related to the current `balance` of a `sender`. Used in transfers.
     * @param sender Address whose tokens are being transferred.
     * @param balance Current balance for the interacting account.
     * @param needed Minimum amount required to perform a transfer.
     * @param tokenId Identifier number of a token.
     */
    error ERC1155InsufficientBalance(address sender, uint256 balance, uint256 needed, uint256 tokenId);

    /**
     * @dev Indicates a failure with the token `sender`. Used in transfers.
     * @param sender Address whose tokens are being transferred.
     */
    error ERC1155InvalidSender(address sender);

    /**
     * @dev Indicates a failure with the token `receiver`. Used in transfers.
     * @param receiver Address to which tokens are being transferred.
     */
    error ERC1155InvalidReceiver(address receiver);

    /**
     * @dev Indicates a failure with the `operator`’s approval. Used in transfers.
     * @param operator Address that may be allowed to operate on tokens without being their owner.
     * @param owner Address of the current owner of a token.
     */
    error ERC1155MissingApprovalForAll(address operator, address owner);

    /**
     * @dev Indicates a failure with the `approver` of a token to be approved. Used in approvals.
     * @param approver Address initiating an approval operation.
     */
    error ERC1155InvalidApprover(address approver);

    /**
     * @dev Indicates a failure with the `operator` to be approved. Used in approvals.
     * @param operator Address that may be allowed to operate on tokens without being their owner.
     */
    error ERC1155InvalidOperator(address operator);

    /**
     * @dev Indicates an array length mismatch between ids and values in a safeBatchTransferFrom operation.
     * Used in batch transfers.
     * @param idsLength Length of the array of token identifiers
     * @param valuesLength Length of the array of token amounts
     */
    error ERC1155InvalidArrayLength(uint256 idsLength, uint256 valuesLength);
}

// lib/openzeppelin-contracts/contracts/interfaces/IERC165.sol

// OpenZeppelin Contracts (last updated v5.4.0) (interfaces/IERC165.sol)

// lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol

// OpenZeppelin Contracts (last updated v5.4.0) (interfaces/IERC20.sol)

// lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol

// OpenZeppelin Contracts (last updated v5.4.0) (token/ERC20/extensions/IERC20Metadata.sol)

/**
 * @dev Interface for the optional metadata functions from the ERC-20 standard.
 */
interface IERC20Metadata is IERC20 {
    /**
     * @dev Returns the name of the token.
     */
    function name() external view returns (string memory);

    /**
     * @dev Returns the symbol of the token.
     */
    function symbol() external view returns (string memory);

    /**
     * @dev Returns the decimals places of the token.
     */
    function decimals() external view returns (uint8);
}

// lib/openzeppelin-contracts/contracts/utils/ReentrancyGuardTransient.sol

// OpenZeppelin Contracts (last updated v5.3.0) (utils/ReentrancyGuardTransient.sol)

/**
 * @dev Variant of {ReentrancyGuard} that uses transient storage.
 *
 * NOTE: This variant only works on networks where EIP-1153 is available.
 *
 * _Available since v5.1._
 */
abstract contract ReentrancyGuardTransient {
    using TransientSlot for *;

    // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.ReentrancyGuard")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant REENTRANCY_GUARD_STORAGE =
        0x9b779b17422d0df92223018b32b4d1fa46e071723d6817e2486d003becc55f00;

    /**
     * @dev Unauthorized reentrant call.
     */
    error ReentrancyGuardReentrantCall();

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     * Calling a `nonReentrant` function from another `nonReentrant`
     * function is not supported. It is possible to prevent this from happening
     * by making the `nonReentrant` function external, and making it call a
     * `private` function that does the actual work.
     */
    modifier nonReentrant() {
        _nonReentrantBefore();
        _;
        _nonReentrantAfter();
    }

    function _nonReentrantBefore() private {
        // On the first call to nonReentrant, REENTRANCY_GUARD_STORAGE.asBoolean().tload() will be false
        if (_reentrancyGuardEntered()) {
            revert ReentrancyGuardReentrantCall();
        }

        // Any calls to nonReentrant after this point will fail
        REENTRANCY_GUARD_STORAGE.asBoolean().tstore(true);
    }

    function _nonReentrantAfter() private {
        REENTRANCY_GUARD_STORAGE.asBoolean().tstore(false);
    }

    /**
     * @dev Returns true if the reentrancy guard is currently set to "entered", which indicates there is a
     * `nonReentrant` function in the call stack.
     */
    function _reentrancyGuardEntered() internal view returns (bool) {
        return REENTRANCY_GUARD_STORAGE.asBoolean().tload();
    }
}

// lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol

// OpenZeppelin Contracts (last updated v5.4.0) (token/ERC20/ERC20.sol)

/**
 * @dev Implementation of the {IERC20} interface.
 *
 * This implementation is agnostic to the way tokens are created. This means
 * that a supply mechanism has to be added in a derived contract using {_mint}.
 *
 * TIP: For a detailed writeup see our guide
 * https://forum.openzeppelin.com/t/how-to-implement-erc20-supply-mechanisms/226[How
 * to implement supply mechanisms].
 *
 * The default value of {decimals} is 18. To change this, you should override
 * this function so it returns a different value.
 *
 * We have followed general OpenZeppelin Contracts guidelines: functions revert
 * instead returning `false` on failure. This behavior is nonetheless
 * conventional and does not conflict with the expectations of ERC-20
 * applications.
 */
abstract contract ERC20 is Context, IERC20, IERC20Metadata, IERC20Errors {
    mapping(address account => uint256) private _balances;

    mapping(address account => mapping(address spender => uint256)) private _allowances;

    uint256 private _totalSupply;

    string private _name;
    string private _symbol;

    /**
     * @dev Sets the values for {name} and {symbol}.
     *
     * Both values are immutable: they can only be set once during construction.
     */
    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
    }

    /**
     * @dev Returns the name of the token.
     */
    function name() public view virtual returns (string memory) {
        return _name;
    }

    /**
     * @dev Returns the symbol of the token, usually a shorter version of the
     * name.
     */
    function symbol() public view virtual returns (string memory) {
        return _symbol;
    }

    /**
     * @dev Returns the number of decimals used to get its user representation.
     * For example, if `decimals` equals `2`, a balance of `505` tokens should
     * be displayed to a user as `5.05` (`505 / 10 ** 2`).
     *
     * Tokens usually opt for a value of 18, imitating the relationship between
     * Ether and Wei. This is the default value returned by this function, unless
     * it's overridden.
     *
     * NOTE: This information is only used for _display_ purposes: it in
     * no way affects any of the arithmetic of the contract, including
     * {IERC20-balanceOf} and {IERC20-transfer}.
     */
    function decimals() public view virtual returns (uint8) {
        return 18;
    }

    /// @inheritdoc IERC20
    function totalSupply() public view virtual returns (uint256) {
        return _totalSupply;
    }

    /// @inheritdoc IERC20
    function balanceOf(address account) public view virtual returns (uint256) {
        return _balances[account];
    }

    /**
     * @dev See {IERC20-transfer}.
     *
     * Requirements:
     *
     * - `to` cannot be the zero address.
     * - the caller must have a balance of at least `value`.
     */
    function transfer(address to, uint256 value) public virtual returns (bool) {
        address owner = _msgSender();
        _transfer(owner, to, value);
        return true;
    }

    /// @inheritdoc IERC20
    function allowance(address owner, address spender) public view virtual returns (uint256) {
        return _allowances[owner][spender];
    }

    /**
     * @dev See {IERC20-approve}.
     *
     * NOTE: If `value` is the maximum `uint256`, the allowance is not updated on
     * `transferFrom`. This is semantically equivalent to an infinite approval.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function approve(address spender, uint256 value) public virtual returns (bool) {
        address owner = _msgSender();
        _approve(owner, spender, value);
        return true;
    }

    /**
     * @dev See {IERC20-transferFrom}.
     *
     * Skips emitting an {Approval} event indicating an allowance update. This is not
     * required by the ERC. See {xref-ERC20-_approve-address-address-uint256-bool-}[_approve].
     *
     * NOTE: Does not update the allowance if the current allowance
     * is the maximum `uint256`.
     *
     * Requirements:
     *
     * - `from` and `to` cannot be the zero address.
     * - `from` must have a balance of at least `value`.
     * - the caller must have allowance for ``from``'s tokens of at least
     * `value`.
     */
    function transferFrom(address from, address to, uint256 value) public virtual returns (bool) {
        address spender = _msgSender();
        _spendAllowance(from, spender, value);
        _transfer(from, to, value);
        return true;
    }

    /**
     * @dev Moves a `value` amount of tokens from `from` to `to`.
     *
     * This internal function is equivalent to {transfer}, and can be used to
     * e.g. implement automatic token fees, slashing mechanisms, etc.
     *
     * Emits a {Transfer} event.
     *
     * NOTE: This function is not virtual, {_update} should be overridden instead.
     */
    function _transfer(address from, address to, uint256 value) internal {
        if (from == address(0)) {
            revert ERC20InvalidSender(address(0));
        }
        if (to == address(0)) {
            revert ERC20InvalidReceiver(address(0));
        }
        _update(from, to, value);
    }

    /**
     * @dev Transfers a `value` amount of tokens from `from` to `to`, or alternatively mints (or burns) if `from`
     * (or `to`) is the zero address. All customizations to transfers, mints, and burns should be done by overriding
     * this function.
     *
     * Emits a {Transfer} event.
     */
    function _update(address from, address to, uint256 value) internal virtual {
        if (from == address(0)) {
            // Overflow check required: The rest of the code assumes that totalSupply never overflows
            _totalSupply += value;
        } else {
            uint256 fromBalance = _balances[from];
            if (fromBalance < value) {
                revert ERC20InsufficientBalance(from, fromBalance, value);
            }
            unchecked {
                // Overflow not possible: value <= fromBalance <= totalSupply.
                _balances[from] = fromBalance - value;
            }
        }

        if (to == address(0)) {
            unchecked {
                // Overflow not possible: value <= totalSupply or value <= fromBalance <= totalSupply.
                _totalSupply -= value;
            }
        } else {
            unchecked {
                // Overflow not possible: balance + value is at most totalSupply, which we know fits into a uint256.
                _balances[to] += value;
            }
        }

        emit Transfer(from, to, value);
    }

    /**
     * @dev Creates a `value` amount of tokens and assigns them to `account`, by transferring it from address(0).
     * Relies on the `_update` mechanism
     *
     * Emits a {Transfer} event with `from` set to the zero address.
     *
     * NOTE: This function is not virtual, {_update} should be overridden instead.
     */
    function _mint(address account, uint256 value) internal {
        if (account == address(0)) {
            revert ERC20InvalidReceiver(address(0));
        }
        _update(address(0), account, value);
    }

    /**
     * @dev Destroys a `value` amount of tokens from `account`, lowering the total supply.
     * Relies on the `_update` mechanism.
     *
     * Emits a {Transfer} event with `to` set to the zero address.
     *
     * NOTE: This function is not virtual, {_update} should be overridden instead
     */
    function _burn(address account, uint256 value) internal {
        if (account == address(0)) {
            revert ERC20InvalidSender(address(0));
        }
        _update(account, address(0), value);
    }

    /**
     * @dev Sets `value` as the allowance of `spender` over the `owner`'s tokens.
     *
     * This internal function is equivalent to `approve`, and can be used to
     * e.g. set automatic allowances for certain subsystems, etc.
     *
     * Emits an {Approval} event.
     *
     * Requirements:
     *
     * - `owner` cannot be the zero address.
     * - `spender` cannot be the zero address.
     *
     * Overrides to this logic should be done to the variant with an additional `bool emitEvent` argument.
     */
    function _approve(address owner, address spender, uint256 value) internal {
        _approve(owner, spender, value, true);
    }

    /**
     * @dev Variant of {_approve} with an optional flag to enable or disable the {Approval} event.
     *
     * By default (when calling {_approve}) the flag is set to true. On the other hand, approval changes made by
     * `_spendAllowance` during the `transferFrom` operation set the flag to false. This saves gas by not emitting any
     * `Approval` event during `transferFrom` operations.
     *
     * Anyone who wishes to continue emitting `Approval` events on the`transferFrom` operation can force the flag to
     * true using the following override:
     *
     * ```solidity
     * function _approve(address owner, address spender, uint256 value, bool) internal virtual override {
     *     super._approve(owner, spender, value, true);
     * }
     * ```
     *
     * Requirements are the same as {_approve}.
     */
    function _approve(address owner, address spender, uint256 value, bool emitEvent) internal virtual {
        if (owner == address(0)) {
            revert ERC20InvalidApprover(address(0));
        }
        if (spender == address(0)) {
            revert ERC20InvalidSpender(address(0));
        }
        _allowances[owner][spender] = value;
        if (emitEvent) {
            emit Approval(owner, spender, value);
        }
    }

    /**
     * @dev Updates `owner`'s allowance for `spender` based on spent `value`.
     *
     * Does not update the allowance value in case of infinite allowance.
     * Revert if not enough allowance is available.
     *
     * Does not emit an {Approval} event.
     */
    function _spendAllowance(address owner, address spender, uint256 value) internal virtual {
        uint256 currentAllowance = allowance(owner, spender);
        if (currentAllowance < type(uint256).max) {
            if (currentAllowance < value) {
                revert ERC20InsufficientAllowance(spender, currentAllowance, value);
            }
            unchecked {
                _approve(owner, spender, currentAllowance - value, false);
            }
        }
    }
}

// lib/openzeppelin-contracts/contracts/interfaces/IERC1363.sol

// OpenZeppelin Contracts (last updated v5.4.0) (interfaces/IERC1363.sol)

/**
 * @title IERC1363
 * @dev Interface of the ERC-1363 standard as defined in the https://eips.ethereum.org/EIPS/eip-1363[ERC-1363].
 *
 * Defines an extension interface for ERC-20 tokens that supports executing code on a recipient contract
 * after `transfer` or `transferFrom`, or code on a spender contract after `approve`, in a single transaction.
 */
interface IERC1363 is IERC20, IERC165 {
    /*
     * Note: the ERC-165 identifier for this interface is 0xb0202a11.
     * 0xb0202a11 ===
     *   bytes4(keccak256('transferAndCall(address,uint256)')) ^
     *   bytes4(keccak256('transferAndCall(address,uint256,bytes)')) ^
     *   bytes4(keccak256('transferFromAndCall(address,address,uint256)')) ^
     *   bytes4(keccak256('transferFromAndCall(address,address,uint256,bytes)')) ^
     *   bytes4(keccak256('approveAndCall(address,uint256)')) ^
     *   bytes4(keccak256('approveAndCall(address,uint256,bytes)'))
     */

    /**
     * @dev Moves a `value` amount of tokens from the caller's account to `to`
     * and then calls {IERC1363Receiver-onTransferReceived} on `to`.
     * @param to The address which you want to transfer to.
     * @param value The amount of tokens to be transferred.
     * @return A boolean value indicating whether the operation succeeded unless throwing.
     */
    function transferAndCall(address to, uint256 value) external returns (bool);

    /**
     * @dev Moves a `value` amount of tokens from the caller's account to `to`
     * and then calls {IERC1363Receiver-onTransferReceived} on `to`.
     * @param to The address which you want to transfer to.
     * @param value The amount of tokens to be transferred.
     * @param data Additional data with no specified format, sent in call to `to`.
     * @return A boolean value indicating whether the operation succeeded unless throwing.
     */
    function transferAndCall(address to, uint256 value, bytes calldata data) external returns (bool);

    /**
     * @dev Moves a `value` amount of tokens from `from` to `to` using the allowance mechanism
     * and then calls {IERC1363Receiver-onTransferReceived} on `to`.
     * @param from The address which you want to send tokens from.
     * @param to The address which you want to transfer to.
     * @param value The amount of tokens to be transferred.
     * @return A boolean value indicating whether the operation succeeded unless throwing.
     */
    function transferFromAndCall(address from, address to, uint256 value) external returns (bool);

    /**
     * @dev Moves a `value` amount of tokens from `from` to `to` using the allowance mechanism
     * and then calls {IERC1363Receiver-onTransferReceived} on `to`.
     * @param from The address which you want to send tokens from.
     * @param to The address which you want to transfer to.
     * @param value The amount of tokens to be transferred.
     * @param data Additional data with no specified format, sent in call to `to`.
     * @return A boolean value indicating whether the operation succeeded unless throwing.
     */
    function transferFromAndCall(address from, address to, uint256 value, bytes calldata data) external returns (bool);

    /**
     * @dev Sets a `value` amount of tokens as the allowance of `spender` over the
     * caller's tokens and then calls {IERC1363Spender-onApprovalReceived} on `spender`.
     * @param spender The address which will spend the funds.
     * @param value The amount of tokens to be spent.
     * @return A boolean value indicating whether the operation succeeded unless throwing.
     */
    function approveAndCall(address spender, uint256 value) external returns (bool);

    /**
     * @dev Sets a `value` amount of tokens as the allowance of `spender` over the
     * caller's tokens and then calls {IERC1363Spender-onApprovalReceived} on `spender`.
     * @param spender The address which will spend the funds.
     * @param value The amount of tokens to be spent.
     * @param data Additional data with no specified format, sent in call to `spender`.
     * @return A boolean value indicating whether the operation succeeded unless throwing.
     */
    function approveAndCall(address spender, uint256 value, bytes calldata data) external returns (bool);
}

// lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol

// OpenZeppelin Contracts (last updated v5.3.0) (token/ERC20/utils/SafeERC20.sol)

/**
 * @title SafeERC20
 * @dev Wrappers around ERC-20 operations that throw on failure (when the token
 * contract returns false). Tokens that return no value (and instead revert or
 * throw on failure) are also supported, non-reverting calls are assumed to be
 * successful.
 * To use this library you can add a `using SafeERC20 for IERC20;` statement to your contract,
 * which allows you to call the safe operations as `token.safeTransfer(...)`, etc.
 */
library SafeERC20 {
    /**
     * @dev An operation with an ERC-20 token failed.
     */
    error SafeERC20FailedOperation(address token);

    /**
     * @dev Indicates a failed `decreaseAllowance` request.
     */
    error SafeERC20FailedDecreaseAllowance(address spender, uint256 currentAllowance, uint256 requestedDecrease);

    /**
     * @dev Transfer `value` amount of `token` from the calling contract to `to`. If `token` returns no value,
     * non-reverting calls are assumed to be successful.
     */
    function safeTransfer(IERC20 token, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeCall(token.transfer, (to, value)));
    }

    /**
     * @dev Transfer `value` amount of `token` from `from` to `to`, spending the approval given by `from` to the
     * calling contract. If `token` returns no value, non-reverting calls are assumed to be successful.
     */
    function safeTransferFrom(IERC20 token, address from, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeCall(token.transferFrom, (from, to, value)));
    }

    /**
     * @dev Variant of {safeTransfer} that returns a bool instead of reverting if the operation is not successful.
     */
    function trySafeTransfer(IERC20 token, address to, uint256 value) internal returns (bool) {
        return _callOptionalReturnBool(token, abi.encodeCall(token.transfer, (to, value)));
    }

    /**
     * @dev Variant of {safeTransferFrom} that returns a bool instead of reverting if the operation is not successful.
     */
    function trySafeTransferFrom(IERC20 token, address from, address to, uint256 value) internal returns (bool) {
        return _callOptionalReturnBool(token, abi.encodeCall(token.transferFrom, (from, to, value)));
    }

    /**
     * @dev Increase the calling contract's allowance toward `spender` by `value`. If `token` returns no value,
     * non-reverting calls are assumed to be successful.
     *
     * IMPORTANT: If the token implements ERC-7674 (ERC-20 with temporary allowance), and if the "client"
     * smart contract uses ERC-7674 to set temporary allowances, then the "client" smart contract should avoid using
     * this function. Performing a {safeIncreaseAllowance} or {safeDecreaseAllowance} operation on a token contract
     * that has a non-zero temporary allowance (for that particular owner-spender) will result in unexpected behavior.
     */
    function safeIncreaseAllowance(IERC20 token, address spender, uint256 value) internal {
        uint256 oldAllowance = token.allowance(address(this), spender);
        forceApprove(token, spender, oldAllowance + value);
    }

    /**
     * @dev Decrease the calling contract's allowance toward `spender` by `requestedDecrease`. If `token` returns no
     * value, non-reverting calls are assumed to be successful.
     *
     * IMPORTANT: If the token implements ERC-7674 (ERC-20 with temporary allowance), and if the "client"
     * smart contract uses ERC-7674 to set temporary allowances, then the "client" smart contract should avoid using
     * this function. Performing a {safeIncreaseAllowance} or {safeDecreaseAllowance} operation on a token contract
     * that has a non-zero temporary allowance (for that particular owner-spender) will result in unexpected behavior.
     */
    function safeDecreaseAllowance(IERC20 token, address spender, uint256 requestedDecrease) internal {
        unchecked {
            uint256 currentAllowance = token.allowance(address(this), spender);
            if (currentAllowance < requestedDecrease) {
                revert SafeERC20FailedDecreaseAllowance(spender, currentAllowance, requestedDecrease);
            }
            forceApprove(token, spender, currentAllowance - requestedDecrease);
        }
    }

    /**
     * @dev Set the calling contract's allowance toward `spender` to `value`. If `token` returns no value,
     * non-reverting calls are assumed to be successful. Meant to be used with tokens that require the approval
     * to be set to zero before setting it to a non-zero value, such as USDT.
     *
     * NOTE: If the token implements ERC-7674, this function will not modify any temporary allowance. This function
     * only sets the "standard" allowance. Any temporary allowance will remain active, in addition to the value being
     * set here.
     */
    function forceApprove(IERC20 token, address spender, uint256 value) internal {
        bytes memory approvalCall = abi.encodeCall(token.approve, (spender, value));

        if (!_callOptionalReturnBool(token, approvalCall)) {
            _callOptionalReturn(token, abi.encodeCall(token.approve, (spender, 0)));
            _callOptionalReturn(token, approvalCall);
        }
    }

    /**
     * @dev Performs an {ERC1363} transferAndCall, with a fallback to the simple {ERC20} transfer if the target has no
     * code. This can be used to implement an {ERC721}-like safe transfer that rely on {ERC1363} checks when
     * targeting contracts.
     *
     * Reverts if the returned value is other than `true`.
     */
    function transferAndCallRelaxed(IERC1363 token, address to, uint256 value, bytes memory data) internal {
        if (to.code.length == 0) {
            safeTransfer(token, to, value);
        } else if (!token.transferAndCall(to, value, data)) {
            revert SafeERC20FailedOperation(address(token));
        }
    }

    /**
     * @dev Performs an {ERC1363} transferFromAndCall, with a fallback to the simple {ERC20} transferFrom if the target
     * has no code. This can be used to implement an {ERC721}-like safe transfer that rely on {ERC1363} checks when
     * targeting contracts.
     *
     * Reverts if the returned value is other than `true`.
     */
    function transferFromAndCallRelaxed(
        IERC1363 token,
        address from,
        address to,
        uint256 value,
        bytes memory data
    ) internal {
        if (to.code.length == 0) {
            safeTransferFrom(token, from, to, value);
        } else if (!token.transferFromAndCall(from, to, value, data)) {
            revert SafeERC20FailedOperation(address(token));
        }
    }

    /**
     * @dev Performs an {ERC1363} approveAndCall, with a fallback to the simple {ERC20} approve if the target has no
     * code. This can be used to implement an {ERC721}-like safe transfer that rely on {ERC1363} checks when
     * targeting contracts.
     *
     * NOTE: When the recipient address (`to`) has no code (i.e. is an EOA), this function behaves as {forceApprove}.
     * Opposedly, when the recipient address (`to`) has code, this function only attempts to call {ERC1363-approveAndCall}
     * once without retrying, and relies on the returned value to be true.
     *
     * Reverts if the returned value is other than `true`.
     */
    function approveAndCallRelaxed(IERC1363 token, address to, uint256 value, bytes memory data) internal {
        if (to.code.length == 0) {
            forceApprove(token, to, value);
        } else if (!token.approveAndCall(to, value, data)) {
            revert SafeERC20FailedOperation(address(token));
        }
    }

    /**
     * @dev Imitates a Solidity high-level call (i.e. a regular function call to a contract), relaxing the requirement
     * on the return value: the return value is optional (but if data is returned, it must not be false).
     * @param token The token targeted by the call.
     * @param data The call data (encoded using abi.encode or one of its variants).
     *
     * This is a variant of {_callOptionalReturnBool} that reverts if call fails to meet the requirements.
     */
    function _callOptionalReturn(IERC20 token, bytes memory data) private {
        uint256 returnSize;
        uint256 returnValue;
        assembly ("memory-safe") {
            let success := call(gas(), token, 0, add(data, 0x20), mload(data), 0, 0x20)
            // bubble errors
            if iszero(success) {
                let ptr := mload(0x40)
                returndatacopy(ptr, 0, returndatasize())
                revert(ptr, returndatasize())
            }
            returnSize := returndatasize()
            returnValue := mload(0)
        }

        if (returnSize == 0 ? address(token).code.length == 0 : returnValue != 1) {
            revert SafeERC20FailedOperation(address(token));
        }
    }

    /**
     * @dev Imitates a Solidity high-level call (i.e. a regular function call to a contract), relaxing the requirement
     * on the return value: the return value is optional (but if data is returned, it must not be false).
     * @param token The token targeted by the call.
     * @param data The call data (encoded using abi.encode or one of its variants).
     *
     * This is a variant of {_callOptionalReturn} that silently catches all reverts and returns a bool instead.
     */
    function _callOptionalReturnBool(IERC20 token, bytes memory data) private returns (bool) {
        bool success;
        uint256 returnSize;
        uint256 returnValue;
        assembly ("memory-safe") {
            success := call(gas(), token, 0, add(data, 0x20), mload(data), 0, 0x20)
            returnSize := returndatasize()
            returnValue := mload(0)
        }
        return success && (returnSize == 0 ? address(token).code.length > 0 : returnValue == 1);
    }
}

// src/Strategy.sol

/**
 * @title GigaETH
 * @dev ERC20 token backed by MEGA with daily lottery and auction mechanics
 * - During minting period: 1000 MEGA = 1 GIGA (MEGA 18 decimals, GIGA 21 decimals)
 * - Redemption: Proportional share of contract's MEGA (GIGA * MEGA balance / total supply)
 * - 1% fee on mint/burn/transfer (split between lottery and auction pools)
 * - Daily lottery for random holder using prevrandao
 * - Daily auctions using ERC20 MEGA
 * - Users can lock community tokens during minting period to mint without fees (optional)
 * - Efficient winner selection using Fenwick tree (Binary Indexed Tree)
 * - Uses transient storage for reentrancy guard (EIP-1153) for gas efficiency
 */
contract Strategy is ERC20, ReentrancyGuardTransient {
    using SafeERC20 for IERC20;
    // Conversion: 1000 MEGA = 1 GIGA (MEGA has 18 decimals, GIGA has 21 decimals)
    uint256 private constant DECIMALS = 21;
    uint256 public constant FEE_PERCENT = 100; // 1% = 100 basis points
    uint256 public constant BASIS_POINTS = 10_000;
    uint256 public constant MINTING_PERIOD = 3 days;
    uint256 public constant COMMUNITY_TOKEN_LOCK_AMOUNT = 100e24;
    uint256 public constant COMMUNITY_TOKEN_UNLOCK_TIME = 30 days; // 1 month from deployment

    // Synthetic addresses for fee management
    address public constant FEES_POOL =
        0x00000000000fee50000000AdD2E5500000000000; // Where fees are collected
    address public constant LOT_POOL =
        0x0000000000010700000000aDD2E5500000000000; // Where lottery/auction prizes are held

    uint256 public immutable deploymentTime;
    uint256 public immutable mintingEndTime;

    // Packed storage slot: 112 + 32 + 8 = 152 bits (fits in one 256-bit slot)
    uint112 public maxSupplyEver; // Set after minting period (max ~5.2 quadrillion GIGA with 18 decimals)
    uint32 public lastLotteryDay; // Day counter (sufficient for ~11.7 million years)
    uint8 public currentBeneficiaryIndex; // Index in BENEFICIARIES array (max 255 addresses)

    uint256 public constant TIME_GAP = 1 minutes; // Must be 1 minute into new day before lottery can execute
    uint256 public constant MIN_FEES_FOR_DISTRIBUTION = 1e12; // Minimum fees (0.000001 GIGA) to run lottery/auction

    // Cyclical arrays for unclaimed prizes (7 slots each)
    // Separate arrays for lottery and auction to prevent slot conflicts
    // We need 7 slots to ensure a full week of unclaimed prizes for each type
    // Since lottery and auction alternate daily after minting period, 7 slots is sufficient
    // Packed struct: 160 + 112 = 272 bits (exceeds 256, uses 2 slots per prize)
    struct UnclaimedPrize {
        address winner; // 160 bits
        uint112 amount; // 112 bits (GIGA amount for prizes)
    }

    UnclaimedPrize[7] public lotteryUnclaimedPrizes;
    UnclaimedPrize[7] public auctionUnclaimedPrizes;

    // Beneficiary recipients (hardcoded)
    address[1] public BENEFICIARIES = [
        0x5000Ff6Cc1864690d947B864B9FB0d603E8d1F1A // Treasury
    ];

    // Struct to maintain rolling 2-day history for each value
    // Stores current and previous value with the day of last update
    // Optimized to fit in one 256-bit storage slot
    struct DualState {
        uint112 olderValue; // Previous value before last update (112 bits)
        uint112 latestValue; // Most recent value (112 bits)
        uint32 lastUpdatedDay; // Day when latestValue was set (32 bits)
        // Total: 256 bits (fits exactly in 1 storage slot)
    }

    // For addresses, we need a separate struct since addresses are 160 bits
    struct DualAddress {
        address olderValue;
        address latestValue;
        uint32 lastUpdatedDay;
    }

    // Holder tracking with rolling 2-day history
    mapping(uint256 index => DualAddress) public holderByIndex;
    mapping(address holder => DualState) public indexByHolder;
    mapping(uint256 index => DualState) public fenwickTree;
    DualState public holderCount;
    DualState public totalHolderBalance;

    // Community token integration
    // Set this to address(0) to disable fee-free minting feature
    // Or set to your community token address before deployment
    IERC20 public constant COMMUNITY_TOKEN = IERC20(address(0));

    // MEGA token (ERC20) - the backing asset for GIGA
    IERC20 public immutable mega;

    // Track MEGA escrowed for auction bids (separate from reserve)
    // This ensures bid amounts don't inflate the apparent reserve
    uint256 public escrowedBidMega;

    // Track community tokens locked per user during minting period
    mapping(address user => uint256 amount) public communityTokenLocked;

    event Minted(
        address indexed to,
        uint256 collateralAmount,
        uint256 tokenAmount,
        uint256 fee
    );
    event Redeemed(
        address indexed from,
        uint256 tokenAmount,
        uint256 collateralAmount,
        uint256 fee
    );
    event LotteryWon(address indexed winner, uint256 amount, uint256 day);
    event PrizeClaimed(address indexed winner, uint256 amount);
    event BeneficiaryFunded(
        address indexed beneficiary,
        uint256 amount,
        address previousWinner
    );
    event CommunityTokenLocked(
        address indexed user,
        uint256 tokenAmount,
        uint256 stratMinted,
        uint256 unlockTime
    );
    event CommunityTokenUnlocked(address indexed user, uint256 amount);

    // Auction events
    event AuctionStarted(uint256 day, uint256 tokenAmount, uint256 minBid);
    event BidPlaced(address indexed bidder, uint256 amount, uint256 day);
    event BidRefunded(address indexed bidder, uint256 amount);
    event AuctionWon(
        address indexed winner,
        uint256 tokenAmount,
        uint256 nativePaid,
        uint256 day
    );

    // Auction state
    // Packed struct: 160 + 96 + 96 + 112 + 32 = 496 bits (uses 2 slots)
    struct Auction {
        address currentBidder; // 160 bits
        uint96 currentBid; // 96 bits - WMEGA amount bid
        uint96 minBid; // 96 bits - Minimum bid required (in WMEGA)
        uint112 auctionTokens; // 112 bits - GIGA amount being auctioned
        uint32 auctionDay; // 32 bits - Day of the auction
    }

    Auction public currentAuction;

    /**
     * @param _mega Address of MEGA ERC20 token (the backing asset)
     */
    constructor(address _mega) ERC20("GigaETH", "GIGA") {
        deploymentTime = block.timestamp;
        mintingEndTime = deploymentTime + MINTING_PERIOD;
        mega = IERC20(_mega);
    }

    function decimals() public pure override returns (uint8) {
        return uint8(DECIMALS);
    }

    /**
     * @dev Get the MEGA reserve (total MEGA balance minus escrowed bid amounts)
     * This is the actual backing for GIGA tokens, excluding auction bid escrow
     */
    function getMegaReserve() public view returns (uint256) {
        return mega.balanceOf(address(this)) - escrowedBidMega;
    }

    /**
     * @dev Check and set max supply after minting period ends
     */
    function _checkAndSetMaxSupply() internal {
        if (maxSupplyEver == 0 && block.timestamp > mintingEndTime) {
            // Set max supply based on total supply at end of minting period
            // 1:1 conversion - max supply equals total GIGA minted
            maxSupplyEver = uint112(totalSupply());
        }
    }

    /**
     * @dev Reject native ETH transfers - use mint() with ERC20 MEGA instead
     */
    receive() external payable {
        revert("Use mint() with ERC20 MEGA");
    }

    /**
     * @dev Mint GIGA by depositing MEGA (standard minting with fees)
     * During minting period: 1000 MEGA = 1 GIGA (1:1 in base units)
     * After minting period: Can only mint up to available capacity
     * @param collateralAmount Amount of MEGA to deposit (requires prior approval)
     */
    function mint(uint256 collateralAmount) external nonReentrant {
        require(collateralAmount > 0, "Must send MEGA");

        // Check and set max supply before any potential burns
        _checkAndSetMaxSupply();

        // Try to execute pending lottery/auction before changing state
        _tryExecuteLotteryAndAuction();

        uint256 tokensToMint;
        uint256 fee;
        uint256 netTokens;

        // Get reserve BEFORE transfer for accurate calculation
        uint256 megaReserveBefore = getMegaReserve();

        // Transfer MEGA from user (requires prior approval)
        mega.safeTransferFrom(msg.sender, address(this), collateralAmount);

        if (block.timestamp <= mintingEndTime) {
            // During minting period: 1:1 in base units (1000 MEGA = 1 GIGA in display units)
            tokensToMint = collateralAmount;
        } else {
            // After minting period: proportional to MEGA/supply ratio
            if (totalSupply() > 0 && megaReserveBefore > 0) {
                // Mint proportionally to maintain MEGA backing ratio
                tokensToMint =
                    (collateralAmount * totalSupply()) /
                    megaReserveBefore;
            } else {
                // Fallback to 1:1 if no supply or MEGA
                tokensToMint = collateralAmount;
            }

            require(
                totalSupply() + tokensToMint <= maxSupplyEver,
                "Max supply reached"
            );
            require(tokensToMint >= 100, "Minimum mint amount is 100 wei");
        }

        // Calculate and apply fees (common to both minting periods)
        fee = (tokensToMint * FEE_PERCENT) / BASIS_POINTS;
        netTokens = tokensToMint - fee;

        // Mint uses _atomicUpdate internally, so Fenwick tree is updated atomically
        _mint(msg.sender, netTokens);
        if (fee > 0) {
            _mint(FEES_POOL, fee);
        }

        // No need for manual Fenwick update - handled atomically in _update

        emit Minted(msg.sender, collateralAmount, netTokens, fee);
    }

    /**
     * @dev Mint GIGA fee-free by locking community tokens
     * Each lock allows one fee-free mint
     * 1000 MEGA = 1 GIGA (no fees deducted)
     * Disabled if COMMUNITY_TOKEN is address(0)
     * @param collateralAmount Amount of MEGA to deposit (requires prior approval)
     */
    function mintFeeFree(uint256 collateralAmount) external nonReentrant {
        require(
            address(COMMUNITY_TOKEN) != address(0),
            "Fee-free minting disabled"
        );
        require(collateralAmount > 0, "Must send MEGA");
        require(
            block.timestamp <= mintingEndTime,
            "Fee-free minting only during minting period"
        );

        // Try to execute pending lottery/auction before changing state
        _tryExecuteLotteryAndAuction();

        // Transfer MEGA from user (requires prior approval)
        mega.safeTransferFrom(msg.sender, address(this), collateralAmount);

        // Transfer community tokens from user to lock
        require(
            COMMUNITY_TOKEN.transferFrom(
                msg.sender,
                address(this),
                COMMUNITY_TOKEN_LOCK_AMOUNT
            ),
            "Community token transfer failed"
        );

        // Track locked amount
        communityTokenLocked[msg.sender] += COMMUNITY_TOKEN_LOCK_AMOUNT;

        // Mint without fees, 1:1 in base units (1000 MEGA = 1 GIGA in display units)
        uint256 tokensToMint = collateralAmount;

        // After minting period: enforce max supply limit
        if (block.timestamp > mintingEndTime) {
            require(
                totalSupply() + tokensToMint <= maxSupplyEver,
                "Max supply reached"
            );
        }

        // Mint full amount to user (no fees)
        // _mint uses _atomicUpdate internally, so Fenwick tree is updated atomically
        _mint(msg.sender, tokensToMint);

        emit CommunityTokenLocked(
            msg.sender,
            COMMUNITY_TOKEN_LOCK_AMOUNT,
            tokensToMint,
            deploymentTime + COMMUNITY_TOKEN_UNLOCK_TIME
        );

        emit Minted(msg.sender, collateralAmount, tokensToMint, 0);
    }

    /**
     * @dev Unlock all community tokens after 1 month from deployment
     */
    function unlockCommunityToken() external nonReentrant {
        require(
            address(COMMUNITY_TOKEN) != address(0),
            "Fee-free minting disabled"
        );
        uint256 lockedAmount = communityTokenLocked[msg.sender];
        require(lockedAmount > 0, "No locked community tokens");
        require(
            block.timestamp >= deploymentTime + COMMUNITY_TOKEN_UNLOCK_TIME,
            "Still in lock period (1 month from deployment)"
        );

        // Check and set max supply before any potential burns
        _checkAndSetMaxSupply();

        // Try to execute pending lottery/auction before changing state
        _tryExecuteLotteryAndAuction();

        // Clear user's locked amount
        communityTokenLocked[msg.sender] = 0;

        // Return all locked community tokens
        require(
            COMMUNITY_TOKEN.transfer(msg.sender, lockedAmount),
            "Community token transfer failed"
        );

        emit CommunityTokenUnlocked(msg.sender, lockedAmount);
    }

    /**
     * @dev Redeem GIGA for MEGA
     * Returns proportional share of contract's MEGA reserve (minus 1% fee)
     */
    function redeem(uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must be greater than 0");
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");

        // Check and set max supply before any potential burns
        _checkAndSetMaxSupply();

        // Try to execute pending lottery/auction before changing state
        _tryExecuteLotteryAndAuction();

        uint256 fee = (amount * FEE_PERCENT) / BASIS_POINTS;
        uint256 netTokens = amount - fee;

        // Calculate proportional MEGA to return before state changes
        // Use getMegaReserve() to exclude escrowed bid amounts
        uint256 collateralToReturn = (netTokens * getMegaReserve()) /
            totalSupply();

        // Transfer fees atomically (Fenwick tree updated automatically)
        if (fee > 0) {
            _atomicUpdate(msg.sender, FEES_POOL, fee);
        }

        // Burn the remainder from user atomically (Fenwick tree updated automatically)
        _burn(msg.sender, netTokens);

        // Transfer proportional MEGA back to user
        mega.safeTransfer(msg.sender, collateralToReturn);

        emit Redeemed(msg.sender, amount, collateralToReturn, fee);
    }

    /**
     * @dev Atomic balance update that ensures Fenwick tree consistency
     * This function should be used for ALL internal balance changes to maintain atomicity
     */
    function _atomicUpdate(address from, address to, uint256 value) internal {
        // Get balances BEFORE the update
        uint256 fromBalanceBefore = from != address(0) ? balanceOf(from) : 0;
        uint256 toBalanceBefore = to != address(0) ? balanceOf(to) : 0;

        // Perform the actual balance update
        super._update(from, to, value);

        // Get balances AFTER the update
        uint256 fromBalanceAfter = from != address(0) ? balanceOf(from) : 0;
        uint256 toBalanceAfter = to != address(0) ? balanceOf(to) : 0;

        // Update Fenwick tree atomically with balance changes
        // All filtering (address(0), contracts, synthetic addresses) handled internally
        _updateCumulativeBalancesWithExplicitBalances(
            from,
            fromBalanceBefore,
            fromBalanceAfter
        );

        _updateCumulativeBalancesWithExplicitBalances(
            to,
            toBalanceBefore,
            toBalanceAfter
        );
    }

    /**
     * @dev Override update to apply fees on transfers
     */
    function _update(
        address from,
        address to,
        uint256 value
    ) internal override {
        // Redirect external transfers to this contract or LOT_POOL to FEES_POOL
        // This maintains the invariant: LOT_POOL balance == auction amount + unclaimed prizes
        if (to == address(this) || to == LOT_POOL) {
            _atomicUpdate(from, FEES_POOL, value);
            return;
        }

        // For minting and burning, use atomic update directly (no lottery trigger needed)
        if (from == address(0) || to == address(0)) {
            _atomicUpdate(from, to, value);
            return;
        }

        // Check and set max supply before any potential burns
        _checkAndSetMaxSupply();

        // Try to execute pending lottery/auction before transfers
        // This ensures Fenwick tree consistency and proper snapshot usage
        _tryExecuteLotteryAndAuction();

        // Apply fees for transfers
        uint256 fee = (value * FEE_PERCENT) / BASIS_POINTS;
        uint256 netAmount = value - fee;

        // Use atomic updates for both the transfer and fee
        // This ensures Fenwick tree consistency
        // For self-transfers, we still need to emit the Transfer event
        if (from == to) {
            // Self-transfer: emit event but skip the no-op balance update
            emit Transfer(from, to, netAmount);
        } else {
            // Normal transfer: update balances and emit event via _atomicUpdate
            _atomicUpdate(from, to, netAmount);
        }

        // Transfer fees to fees pool atomically
        if (fee > 0) {
            _atomicUpdate(from, FEES_POOL, fee);
        }
    }

    /**
     * @dev Update a DualState with a new value, preserving history
     */
    function _updateDualState(
        DualState storage state,
        uint112 newValue,
        uint32 currentDay
    ) internal {
        if (state.lastUpdatedDay < currentDay) {
            // New day - shift current to older and set new value
            state.olderValue = state.latestValue;
            state.latestValue = newValue;
            state.lastUpdatedDay = currentDay;
        } else {
            // Same day - just update latest value
            state.latestValue = newValue;
        }
    }

    /**
     * @dev Update a DualAddress with a new value, preserving history
     */
    function _updateDualAddress(
        DualAddress storage state,
        address newValue,
        uint32 currentDay
    ) internal {
        if (state.lastUpdatedDay < currentDay) {
            // New day - shift current to older and set new value
            state.olderValue = state.latestValue;
            state.latestValue = newValue;
            state.lastUpdatedDay = currentDay;
        } else {
            // Same day - just update latest value
            state.latestValue = newValue;
        }
    }

    /**
     * @dev Get value from a DualState for a specific day
     */
    function _getDualStateValue(
        DualState memory state,
        uint32 targetDay
    ) internal pure returns (uint112) {
        if (state.lastUpdatedDay <= targetDay) {
            return state.latestValue;
        }
        return state.olderValue;
    }

    /**
     * @dev Get value from a DualAddress for a specific day
     */
    function _getDualAddressValue(
        DualAddress memory state,
        uint32 targetDay
    ) internal pure returns (address) {
        if (state.lastUpdatedDay <= targetDay) {
            return state.latestValue;
        }
        return state.olderValue;
    }

    /**
     * @dev Update Fenwick tree at index with delta (suffix sum version)
     * For suffix sums, we update positions whose range includes the index
     */
    function _fenwickUpdate(uint256 index, int256 delta) internal {
        uint32 currentDay = uint32(getCurrentDay());

        // Update all nodes whose suffix range includes this index
        // Start from index and move backward
        uint256 i = index;
        while (i > 0) {
            DualState storage treeNode = fenwickTree[i];
            uint112 currentSum = treeNode.latestValue;
            uint112 newSum;

            if (delta > 0) {
                newSum = currentSum + uint112(uint256(delta));
            } else {
                uint112 decrease = uint112(uint256(-delta));
                newSum = currentSum - decrease;
            }

            _updateDualState(treeNode, newSum, currentDay);

            // Move to previous node whose range includes our index
            // For suffix tree: move to i - lowbit(i)
            i -= i & uint256(-int256(i));
        }
    }

    /**
     * @dev Query suffix sum from index to end for a specific day
     * Goes upward using the current holder count as max
     */
    function _fenwickQuery(
        uint256 index,
        uint32 targetDay
    ) internal view returns (uint256) {
        uint256 sum = 0;
        uint112 maxIndex = _getDualStateValue(holderCount, targetDay);

        while (index <= maxIndex) {
            sum += _getDualStateValue(fenwickTree[index], targetDay);
            index += index & uint256(-int256(index)); // Move up the tree
        }
        return sum;
    }

    /**
     * @dev Update holder balance with explicit before/after balances
     */
    function _updateCumulativeBalancesWithExplicitBalances(
        address account,
        uint256 balanceBefore,
        uint256 balanceAfter
    ) internal {
        if (account == address(0)) return; // Skip zero address (minting/burning)
        if (account == LOT_POOL || account == FEES_POOL) return; // Skip synthetic addresses

        uint32 currentDay = uint32(getCurrentDay());
        uint256 currentIndex = indexByHolder[account].latestValue;

        // For contracts: only skip if they're not already in the tree
        // This prevents corruption from constructor bypass or CREATE2 pre-funding
        if (account.code.length > 0 && currentIndex == 0) return;

        int256 balanceChange = int256(balanceAfter) - int256(balanceBefore);

        if (balanceAfter > 0 && currentIndex == 0) {
            // Add new holder
            uint112 newCount = holderCount.latestValue + 1;
            uint112 newTotalBalance = totalHolderBalance.latestValue +
                uint112(balanceAfter);

            _updateDualState(holderCount, newCount, currentDay);
            _updateDualAddress(holderByIndex[newCount], account, currentDay);
            _updateDualState(
                indexByHolder[account],
                uint112(newCount),
                currentDay
            );

            // Update Fenwick tree
            _fenwickUpdate(newCount, int256(balanceAfter));

            _updateDualState(totalHolderBalance, newTotalBalance, currentDay);
        } else if (balanceAfter == 0 && currentIndex > 0) {
            // Remove holder - use the balance before removal
            uint112 currentTotalBalance = totalHolderBalance.latestValue;

            // Update Fenwick tree before removal
            _fenwickUpdate(currentIndex, -int256(balanceBefore));

            uint112 newTotalBalance = currentTotalBalance -
                uint112(balanceBefore);

            _updateDualState(totalHolderBalance, newTotalBalance, currentDay);

            // Compact holders by moving the last holder to the removed position
            uint112 currentCount = holderCount.latestValue;

            if (currentIndex < currentCount) {
                address lastHolder = holderByIndex[currentCount].latestValue;

                // Get the last holder's balance from the Fenwick tree at their position
                // This is their balance BEFORE any concurrent updates
                uint112 lastHolderFenwickBalance = fenwickTree[currentCount]
                    .latestValue;

                // Remove last holder's balance from old position
                _fenwickUpdate(
                    currentCount,
                    -int256(uint256(lastHolderFenwickBalance))
                );

                // Move last holder to current position
                _updateDualAddress(
                    holderByIndex[currentIndex],
                    lastHolder,
                    currentDay
                );
                _updateDualState(
                    indexByHolder[lastHolder],
                    uint112(currentIndex),
                    currentDay
                );

                // Add last holder's balance to new position
                _fenwickUpdate(
                    currentIndex,
                    int256(uint256(lastHolderFenwickBalance))
                );
            }

            // Clear the removed holder's index and last position
            _updateDualState(indexByHolder[account], 0, currentDay);
            _updateDualAddress(
                holderByIndex[currentCount],
                address(0),
                currentDay
            );

            // Decrement holder count
            _updateDualState(holderCount, currentCount - 1, currentDay);
        } else if (currentIndex > 0) {
            // Update existing holder
            // Update Fenwick tree with the difference
            _fenwickUpdate(currentIndex, balanceChange);

            uint112 currentTotalBalance = totalHolderBalance.latestValue;
            uint112 newTotalBalance;

            if (balanceChange > 0) {
                newTotalBalance =
                    currentTotalBalance +
                    uint112(uint256(balanceChange));
            } else {
                uint112 decrease = uint112(uint256(-balanceChange));
                newTotalBalance = currentTotalBalance > decrease
                    ? currentTotalBalance - decrease
                    : 0;
            }

            _updateDualState(totalHolderBalance, newTotalBalance, currentDay);
        }
    }

    /**
     * @dev Internal function to try executing pending lottery and auction
     * Called before state-changing operations to ensure winners are determined first
     */
    function _tryExecuteLotteryAndAuction() internal {
        uint256 currentDay = getCurrentDay();

        // No lottery/auction until day 1 (need previous day's fees)
        if (currentDay < 1) return;

        // If day changed since last lottery, we have a pending lottery/auction
        if (currentDay <= lastLotteryDay) return;

        // Ensure we're at least 1 minute into the new day to prevent manipulation
        uint256 timeIntoDay = (block.timestamp - deploymentTime) % 25 hours;
        if (timeIntoDay < TIME_GAP) return;

        // Get all accumulated fees from FEES_POOL
        uint256 feesToDistribute = balanceOf(FEES_POOL);

        // Skip lottery/auction for dust amounts
        // This ensures both lottery and auction get meaningful amounts when split
        if (feesToDistribute < MIN_FEES_FOR_DISTRIBUTION) return;

        // Run both lottery and auction every day after minting period
        // During minting period, only run lottery with full fees
        if (block.timestamp > mintingEndTime) {
            // Split fees 50/50 between lottery and auction
            uint256 lotteryShare = feesToDistribute / 2;
            uint256 auctionShare = feesToDistribute - lotteryShare; // Handle odd amounts
            _executeLotteryInternal(lotteryShare);
            _startAuction(auctionShare);
        } else {
            _executeLotteryInternal(feesToDistribute);
        }
    }

    /**
     * @dev Internal lottery execution logic
     */
    function _executeLotteryInternal(uint256 feesToDistribute) internal {
        uint256 randomSeed = block.prevrandao;
        uint256 currentDay = getCurrentDay();

        // Use snapshot from previous day (when fees were collected)
        uint32 snapshotDay = uint32(currentDay - 1);

        // Get holder count and total balance from the snapshot day
        uint112 snapshotHolderCount = _getDualStateValue(
            holderCount,
            snapshotDay
        );
        uint112 snapshotTotalBalance = _getDualStateValue(
            totalHolderBalance,
            snapshotDay
        );

        // Select winner if there are holders
        if (snapshotHolderCount > 0 && snapshotTotalBalance > 0) {
            address winner = _selectWinnerEfficient(snapshotDay, randomSeed);

            uint256 lotteryDay = currentDay - 1; // The day whose fees we're distributing
            uint256 slot = lotteryDay % 7; // Use 7 slots for lottery prizes

            // Transfer prize from fees pool to lottery pool for holding
            _atomicUpdate(FEES_POOL, LOT_POOL, feesToDistribute);

            // Check if this slot has an unclaimed lottery prize
            UnclaimedPrize storage prize = lotteryUnclaimedPrizes[slot];
            if (prize.amount > 0) {
                // Try to redeem GIGA for MEGA and send to beneficiary
                address beneficiary = BENEFICIARIES[currentBeneficiaryIndex];
                currentBeneficiaryIndex = uint8(
                    (currentBeneficiaryIndex + 1) % BENEFICIARIES.length
                );

                // Calculate MEGA value of the GIGA prizeToSend
                // MEGA amount = (GIGA amount * MEGA reserve) / total supply
                uint256 collateralToSend = (uint256(prize.amount) *
                    getMegaReserve()) / totalSupply();

                // Attempt to send MEGA to beneficiary using low-level call
                // This handles both standard and non-standard ERC20 implementations
                (bool success, bytes memory data) = address(mega).call(
                    abi.encodeCall(
                        IERC20.transfer,
                        (beneficiary, collateralToSend)
                    )
                );
                success =
                    success &&
                    (data.length == 0 || abi.decode(data, (bool)));

                if (success) {
                    // MEGA transfer successful, now burn the GIGA tokens from lottery pool
                    _burn(LOT_POOL, prize.amount);
                    emit BeneficiaryFunded(
                        beneficiary,
                        collateralToSend, // Emit the actual MEGA amount sent
                        prize.winner
                    );
                } else {
                    // MEGA transfer failed, add unclaimed prize to current winner's prize
                    // The current winner will get both prizes when they claim
                    feesToDistribute += prize.amount;
                    // Note: We still cycle to the next beneficiary for fairness
                }
            }

            // Store new prize in the slot (overwriting any previous data)
            prize.winner = winner;
            prize.amount = uint112(feesToDistribute); // Store GIGA amount as prize

            emit LotteryWon(winner, feesToDistribute, lotteryDay);
        }

        // Update last lottery day
        lastLotteryDay = uint32(currentDay);
    }

    /**
     * @dev Public function to execute daily lottery
     */
    function executeLottery() external nonReentrant {
        uint256 currentDay = getCurrentDay();
        require(
            currentDay >= 1,
            "Must wait until day 1 for first lottery/auction"
        );

        require(
            currentDay > lastLotteryDay,
            "No pending lottery/auction (same day)"
        );

        // Check and set max supply before any potential burns
        _checkAndSetMaxSupply();

        // Ensure we're at least 1 minute into the new day
        uint256 timeIntoDay = (block.timestamp - deploymentTime) % 25 hours;
        require(
            timeIntoDay >= TIME_GAP,
            "Must wait 1 minute into new day before executing"
        );

        // Get all accumulated fees from FEES_POOL
        uint256 feesToDistribute = balanceOf(FEES_POOL);
        require(
            feesToDistribute >= MIN_FEES_FOR_DISTRIBUTION,
            "Insufficient fees to distribute"
        );

        // Split fees 50/50 between lottery and auction
        uint256 lotteryShare = feesToDistribute / 2;
        uint256 auctionShare = feesToDistribute - lotteryShare; // Handle odd amounts

        // Run both lottery and auction every day after minting period
        // During minting period, only run lottery with full fees
        if (block.timestamp > mintingEndTime) {
            _executeLotteryInternal(lotteryShare);
            _startAuction(auctionShare);
        } else {
            _executeLotteryInternal(feesToDistribute);
        }
    }

    /**
     * @dev Claim unclaimed prizes for the caller
     */
    function claim() external nonReentrant {
        // Check and set max supply before any transfers
        _checkAndSetMaxSupply();

        uint256 totalClaimed = 0;

        // Check all 7 slots for both lottery and auction prizes in a single loop
        for (uint256 i = 0; i < 7; i++) {
            // Check lottery prizes
            if (
                lotteryUnclaimedPrizes[i].winner == msg.sender &&
                lotteryUnclaimedPrizes[i].amount > 0
            ) {
                uint256 prizeAmount = lotteryUnclaimedPrizes[i].amount;
                totalClaimed += prizeAmount;

                // Clear the slot
                lotteryUnclaimedPrizes[i].winner = address(0);
                lotteryUnclaimedPrizes[i].amount = 0;

                emit PrizeClaimed(msg.sender, prizeAmount);
            }

            // Check auction prizes
            if (
                auctionUnclaimedPrizes[i].winner == msg.sender &&
                auctionUnclaimedPrizes[i].amount > 0
            ) {
                uint256 prizeAmount = auctionUnclaimedPrizes[i].amount;
                totalClaimed += prizeAmount;

                // Clear the slot
                auctionUnclaimedPrizes[i].winner = address(0);
                auctionUnclaimedPrizes[i].amount = 0;

                emit PrizeClaimed(msg.sender, prizeAmount);
            }
        }

        require(totalClaimed > 0, "No prizes to claim");

        // Transfer all claimed prizes at once from lottery pool
        // _atomicUpdate handles Fenwick tree updates automatically
        _atomicUpdate(LOT_POOL, msg.sender, totalClaimed);
    }

    /**
     * @dev Efficient winner selection using binary search on Fenwick tree (suffix sum version)
     */
    function _selectWinnerEfficient(
        uint32 lotteryDay,
        uint256 randomSeed
    ) internal view returns (address) {
        uint112 snapshotTotalBalance = _getDualStateValue(
            totalHolderBalance,
            lotteryDay
        );
        uint112 snapshotHolderCount = _getDualStateValue(
            holderCount,
            lotteryDay
        );

        // Random number from 1 to total balance
        uint256 winningNumber = (randomSeed % snapshotTotalBalance) + 1;

        // With suffix sums, we want to find the largest index where suffix sum >= winningNumber
        // Since suffix sum decreases as index increases, we search for the transition point
        uint256 left = 1;
        uint256 right = snapshotHolderCount;

        while (left < right) {
            uint256 mid = (left + right + 1) / 2; // Round up to avoid infinite loop
            uint256 suffixSum = _fenwickQuery(mid, lotteryDay);

            if (suffixSum >= winningNumber) {
                // This holder or later could be the winner, try higher index
                left = mid;
            } else {
                // Suffix sum too small, need earlier holder
                right = mid - 1;
            }
        }

        return _getDualAddressValue(holderByIndex[left], lotteryDay);
    }

    /**
     * @dev Get current day number
     * We use 25-hour "pseudo-days" instead of 24-hour days so that over time,
     * the daily lottery/auction transitions happen at different hours of the day.
     * This gives participants from all time zones equal opportunities to participate
     * in the beginning and end of each cycle, preventing any geographic advantage.
     */
    function getCurrentDay() public view returns (uint256) {
        return (block.timestamp - deploymentTime) / 25 hours;
    }

    /**
     * @dev Get holder count (latest value)
     */
    function getHolderCount() external view returns (uint256) {
        return holderCount.latestValue;
    }

    /**
     * @dev Get holder info by index (1-indexed for Fenwick tree)
     */
    function getHolderByIndex(
        uint256 index
    ) external view returns (address holder, uint256 balance) {
        require(
            index > 0 && index <= holderCount.latestValue,
            "Index out of bounds"
        );
        address holderAddress = holderByIndex[index].latestValue;
        return (holderAddress, balanceOf(holderAddress));
    }

    /**
     * @dev Get current lottery pool balance
     */
    function currentLotteryPool() external view returns (uint256) {
        return balanceOf(LOT_POOL);
    }

    /**
     * @dev Check if an address is a holder
     */
    function isHolder(address account) external view returns (bool) {
        return indexByHolder[account].latestValue > 0;
    }

    /**
     * @dev Debug function to get Fenwick tree value at index (for testing)
     */
    function getFenwickValue(uint256 index) external view returns (uint256) {
        return fenwickTree[index].latestValue;
    }

    /**
     * @dev Debug function to get suffix sum from index to end (for testing)
     */
    function getSuffixSum(uint256 index) external view returns (uint256) {
        return _fenwickQuery(index, uint32(getCurrentDay()));
    }

    /**
     * @dev Get claimable amount for the caller
     */
    function getMyClaimableAmount() external view returns (uint256 total) {
        // Check both lottery and auction prizes in a single loop
        for (uint256 i = 0; i < 7; i++) {
            if (lotteryUnclaimedPrizes[i].winner == msg.sender) {
                total += lotteryUnclaimedPrizes[i].amount;
            }
            if (auctionUnclaimedPrizes[i].winner == msg.sender) {
                total += auctionUnclaimedPrizes[i].amount;
            }
        }
    }

    /**
     * @dev Get all unclaimed prizes (both lottery and auction)
     */
    function getAllUnclaimedPrizes()
        external
        view
        returns (
            address[7] memory lotteryWinners,
            uint112[7] memory lotteryAmounts,
            address[7] memory auctionWinners,
            uint112[7] memory auctionAmounts
        )
    {
        for (uint256 i = 0; i < 7; i++) {
            lotteryWinners[i] = lotteryUnclaimedPrizes[i].winner;
            lotteryAmounts[i] = lotteryUnclaimedPrizes[i].amount;
            auctionWinners[i] = auctionUnclaimedPrizes[i].winner;
            auctionAmounts[i] = auctionUnclaimedPrizes[i].amount;
        }
    }

    /**
     * @dev Start an auction for the previous day's fees
     */
    function _startAuction(uint256 feesToDistribute) internal {
        uint256 currentDay = getCurrentDay();

        // Finalize previous auction if it exists
        if (currentAuction.auctionDay != 0) {
            _finalizeAuction();
        }

        // Calculate minimum bid for the GIGA amount being auctioned
        // MinBid = (MEGA reserve * feesToDistribute) / (2 * totalSupply)
        // This sets the minimum bid at 50% of the redemption value
        // Overflow safety: reserve < 2^96, feesToDistribute < 2^112, product < 2^208
        uint256 minBid = (getMegaReserve() * feesToDistribute) /
            (2 * totalSupply());

        // Transfer fees from fees pool to lottery pool for auction
        _atomicUpdate(FEES_POOL, LOT_POOL, feesToDistribute);

        // Start new auction
        currentAuction = Auction({
            currentBidder: address(0),
            currentBid: 0,
            minBid: uint96(minBid),
            auctionTokens: uint112(feesToDistribute),
            auctionDay: uint32(currentDay - 1) // Day whose fees we're auctioning
        });

        emit AuctionStarted(currentDay - 1, feesToDistribute, minBid);

        // Update last lottery day (even though it's an auction, we use same tracking)
        lastLotteryDay = uint32(currentDay);
    }

    /**
     * @dev Finalize the current auction
     */
    function _finalizeAuction() internal {
        // If no bids, roll over the fees to the next day
        if (currentAuction.currentBidder == address(0)) {
            if (currentAuction.auctionTokens > 0) {
                // Add unclaimed auction amount back to fees pool for next distribution
                _atomicUpdate(
                    LOT_POOL,
                    FEES_POOL,
                    currentAuction.auctionTokens
                );
            }
            return;
        }

        uint256 slot = currentAuction.auctionDay % 7; // Use 7 slots for auction prizes

        // Check if this slot has an unclaimed auction prize
        UnclaimedPrize storage prize = auctionUnclaimedPrizes[slot];
        if (prize.amount > 0) {
            // Try to send to beneficiary
            address beneficiary = BENEFICIARIES[currentBeneficiaryIndex];
            currentBeneficiaryIndex = uint8(
                (currentBeneficiaryIndex + 1) % BENEFICIARIES.length
            );

            // Calculate MEGA value of the GIGA prize
            // MEGA amount = (GIGA amount * MEGA reserve) / total supply
            uint256 collateralToSend = (uint256(prize.amount) *
                getMegaReserve()) / totalSupply();

            // Attempt to send MEGA to beneficiary using low-level call
            // This handles both standard and non-standard ERC20 implementations
            (bool success, bytes memory data) = address(mega).call(
                abi.encodeCall(IERC20.transfer, (beneficiary, collateralToSend))
            );
            success = success && (data.length == 0 || abi.decode(data, (bool)));

            if (success) {
                _burn(LOT_POOL, prize.amount);
                emit BeneficiaryFunded(
                    beneficiary,
                    collateralToSend,
                    prize.winner
                ); // Emit actual MEGA amount
            } else {
                // Add to current winner's prize
                currentAuction.auctionTokens += uint112(prize.amount);
            }
        }

        // Move bid MEGA from escrow to reserve (accounting change only)
        // The MEGA tokens are already in the contract, just reclassifying them
        escrowedBidMega -= currentAuction.currentBid;

        // Store new prize
        prize.winner = currentAuction.currentBidder;
        prize.amount = currentAuction.auctionTokens;

        emit AuctionWon(
            currentAuction.currentBidder,
            currentAuction.auctionTokens,
            currentAuction.currentBid,
            currentAuction.auctionDay
        );
    }

    /**
     * @dev Place a bid in the current auction
     * The bidder must have approved MEGA for at least 10% higher than the current bid
     * Winning bid gets the auctioned GIGA tokens
     * Previous bidder gets their MEGA refunded immediately
     *
     * We enforce a 10% minimum increment to make auctions more accessible to non-bot participants.
     * Since token prices rarely change by 10% in a single day, this creates a window where
     * early bidders can speculate on the value without being immediately outbid by bots
     * that might otherwise place marginally higher bids repeatedly.
     *
     * @param bidAmount Amount of MEGA to bid (requires prior approval)
     */
    function bid(uint256 bidAmount) external nonReentrant {
        require(currentAuction.auctionDay != 0, "No active auction");

        // Check and set max supply (for consistency)
        _checkAndSetMaxSupply();

        uint256 currentDay = getCurrentDay();

        // Check if auction is still active (same day)
        require(currentDay == lastLotteryDay, "Auction has ended");

        // Determine minimum bid required
        uint256 minBid = currentAuction.currentBid == 0
            ? currentAuction.minBid // Use stored minimum for first bid
            : (currentAuction.currentBid * 110) / 100; // 10% increase for subsequent bids

        require(bidAmount >= minBid, "Bid too low");

        // Transfer MEGA from bidder (requires prior approval)
        mega.safeTransferFrom(msg.sender, address(this), bidAmount);

        // Track as escrowed (not part of reserve until auction finalizes)
        escrowedBidMega += bidAmount;

        // Store previous bidder info
        address previousBidder = currentAuction.currentBidder;
        uint256 previousBid = currentAuction.currentBid;

        // Update auction state
        currentAuction.currentBidder = msg.sender;
        currentAuction.currentBid = uint96(bidAmount);

        emit BidPlaced(msg.sender, bidAmount, currentAuction.auctionDay);

        // Refund previous bidder if exists
        if (previousBidder != address(0)) {
            // Remove from escrow before transfer
            escrowedBidMega -= previousBid;
            mega.safeTransfer(previousBidder, previousBid);
            emit BidRefunded(previousBidder, previousBid);
        }
    }
}
