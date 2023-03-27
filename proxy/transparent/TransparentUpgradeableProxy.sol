// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.7.0) (proxy/transparent/TransparentUpgradeableProxy.sol)

pragma solidity ^0.8.0;

import "../ERC1967/ERC1967Proxy.sol";

contract TransparentUpgradeableProxy is ERC1967Proxy {
    constructor(
        address _logic,
        address admin_,
        bytes memory _data
    ) payable ERC1967Proxy(_logic, _data) {
        _changeAdmin(admin_);
    }

    modifier ifAdmin() {
        if (msg.sender == _getAdmin()) {
            _;
        } else {
            _fallback();
        }
    }

    function admin() external payable ifAdmin returns (address admin_) {
        _requireZeroValue();
        admin_ = _getAdmin();
    }

    function implementation()
        external
        payable
        ifAdmin
        returns (address implementation_)
    {
        _requireZeroValue();
        implementation_ = _implementation();
    }

    function changeAdmin(address newAdmin) external payable virtual ifAdmin {
        _requireZeroValue();
        _changeAdmin(newAdmin);
    }

    function upgradeTo(address newImplementation) external payable ifAdmin {
        _requireZeroValue();
        _upgradeToAndCall(newImplementation, bytes(""), false);
    }

    function upgradeToAndCall(
        address newImplementation,
        bytes calldata data
    ) external payable ifAdmin {
        _upgradeToAndCall(newImplementation, data, true);
    }

    function _admin() internal view virtual returns (address) {
        return _getAdmin();
    }

    function _beforeFallback() internal virtual override {
        require(
            msg.sender != _getAdmin(),
            "TransparentUpgradeableProxy: admin cannot fallback to proxy target"
        );
        super._beforeFallback();
    }

    function _requireZeroValue() private {
        require(msg.value == 0);
    }
}
