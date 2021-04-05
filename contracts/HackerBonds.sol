/// SPDX-License-Identifier: None
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {IERC20PaymentStandard} from './IERC20PaymentStandard.sol';

contract HackerBonds is ERC1155 {

    constructor() ERC1155("https://test.com/api/{id}.json"){}

    function mintFakes(uint256 _amm, uint256 _id) external{
        _mint(msg.sender, _id, _amm, "");
    }
}

