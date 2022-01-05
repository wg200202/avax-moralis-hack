// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.4;

import "./TNS.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

abstract contract NameResolver {
    function setName(bytes32 node, string memory name) public virtual;
}

bytes32 constant lookup = 0x3031323334353637383961626364656600000000000000000000000000000000;
// namehash('addr.reverse')
bytes32 constant ADDR_REVERSE_NODE = 0x91d1777781884d03a6757a803996e38de2a42967fb37eeaca72729271025a9e2;

contract ReverseRegistrar {
    TNS public tns;
    NameResolver public defaultResolver;

    event ReverseClaimed(address indexed addr, bytes32 indexed node);

    /**
     * @dev Constructor
     * @param tnsAddr The address of the TNS registry.
     * @param resolverAddr The address of the default reverse resolver.
     */
    constructor(TNS tnsAddr, NameResolver resolverAddr) {
        tns = tnsAddr;
        defaultResolver = resolverAddr;

        // Assign ownership of the reverse record to our deployer
        ReverseRegistrar oldRegistrar = ReverseRegistrar(
            tns.owner(ADDR_REVERSE_NODE)
        );
        if (address(oldRegistrar) != address(0x0)) {
            oldRegistrar.claim(msg.sender);
        }
    }

    mapping(address => bool) public controllers;

    event ControllerChanged(address indexed controller, bool enabled);

    modifier onlyController() {
        require(
            controllers[msg.sender],
            "Controllable: Caller is not a controller"
        );
        _;
    }

    /**
     * @dev Transfers ownership of the reverse ENS record associated with the
     *      calling account.
     * @param _owner The address to set as the owner of the reverse record in ENS.
     * @return The TNS node hash of the reverse record.
     */
    function claim(address _owner) public returns (bytes32) {
        return _claimWithResolver(msg.sender, _owner, address(0x0));
    }

    /**
     * @dev Transfers ownership of the reverse ENS record associated with the
     *      calling account.
     * @param _owner The address to set as the owner of the reverse record in ENS.
     * @param resolver The address of the resolver to set; 0 to leave unchanged.
     * @return The ENS node hash of the reverse record.
     */
    function claimWithResolver(address _owner, address resolver)
        public
        returns (bytes32)
    {
        return _claimWithResolver(msg.sender, _owner, resolver);
    }

    /**
     * @dev Transfers ownership of the reverse ENS record specified with the
     *      address provided
     * @param addr The reverse record to set
     * @param owner The address to set as the owner of the reverse record in ENS.
     * @param resolver The address of the resolver to set; 0 to leave unchanged.
     * @return The ENS node hash of the reverse record.
     */
    function claimWithResolverForAddr(
        address addr,
        address owner,
        address resolver
    ) public returns (bytes32) {
        return _claimWithResolver(addr, owner, resolver);
    }

    /**
     * @dev Sets the `name()` record for the reverse ENS record associated with
     * the account provided. First updates the resolver to the default reverse
     * resolver if necessary.
     * Only callable by controllers and authorised users
     * @param addr The reverse record to set
     * @param _owner The owner of the reverse node
     * @param name The name to set for this address.
     * @return The ENS node hash of the reverse record.
     */
    function setNameForAddr(
        address addr,
        address _owner,
        string memory name
    ) public returns (bytes32) {
        bytes32 _node = _claimWithResolver(
            addr,
            address(this),
            address(defaultResolver)
        );
        defaultResolver.setName(_node, name);
        tns.setSubnodeOwner(ADDR_REVERSE_NODE, sha3HexAddress(addr), _owner);
        return _node;
    }

    /**
     * @dev Transfers ownership of the reverse ENS record associated with the
     *      calling account.
     * @param addr The reverse record to set
     * @param owner The address to set as the owner of the reverse record in ENS.
     * @return The ENS node hash of the reverse record.
     */
    function claimForAddr(address addr, address owner)
        public
        returns (bytes32)
    {
        return _claimWithResolver(addr, owner, address(0x0));
    }

    /**
     * @dev Returns the node hash for a given account's reverse records.
     * @param addr The address to hash
     * @return The ENS node hash.
     */
    function node(address addr) public pure returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(ADDR_REVERSE_NODE, sha3HexAddress(addr))
            );
    }

    /**
     * @dev An optimised function to compute the sha3 of the lower-case
     *      hexadecimal representation of an Ethereum address.
     * @param addr The address to hash
     * @return ret The SHA3 hash of the lower-case hexadecimal encoding of the
     *         input address.
     */
    function sha3HexAddress(address addr) private pure returns (bytes32 ret) {
        assembly {
            for {
                let i := 40
            } gt(i, 0) {

            } {
                i := sub(i, 1)
                mstore8(i, byte(and(addr, 0xf), lookup))
                addr := div(addr, 0x10)
                i := sub(i, 1)
                mstore8(i, byte(and(addr, 0xf), lookup))
                addr := div(addr, 0x10)
            }

            ret := keccak256(0, 40)
        }
    }

    /* Internal functions */

    function _claimWithResolver(
        address addr,
        address owner,
        address resolver
    ) internal returns (bytes32) {
        bytes32 label = sha3HexAddress(addr);
        bytes32 _node = keccak256(abi.encodePacked(ADDR_REVERSE_NODE, label));
        address currentResolver = tns.resolver(_node);
        bool shouldUpdateResolver = (resolver != address(0x0) &&
            resolver != currentResolver);
        address newResolver = shouldUpdateResolver ? resolver : currentResolver;

        tns.setSubnodeRecord(ADDR_REVERSE_NODE, label, owner, newResolver);

        emit ReverseClaimed(addr, _node);

        return _node;
    }

    function ownsContract(address addr) internal view returns (bool) {
        try Ownable(addr).owner() returns (address owner) {
            return owner == msg.sender;
        } catch {
            return false;
        }
    }
}
