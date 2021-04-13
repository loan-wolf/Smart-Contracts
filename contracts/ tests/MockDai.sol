/// SPDX-License-Identifier: None
pragma solidity ^0.6.6;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';

/**
* @title MockDai
* @author Carson Case
* @notice just a simple ERC20 to use for testing
 */
contract MockDai is ERC20{
    constructor(uint256 _devFee) ERC20("DAI", "Mock Dai") public{
        _mint(msg.sender, _devFee);
    }
}