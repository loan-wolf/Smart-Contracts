/// SPDX-License-Identifier: None
pragma solidity ^0.8.0;

import "./ERC20PaymentStandard.sol";
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

/**
* @title ERC20CollateralPayment
* @author Carson Case
* @notice this is an example of a override of ERC20PaymentStandard. This offers ERC20 collateral to be be added
 */
contract ERC20CollateralPayment is ERC20PaymentStandard{
    /// @notice collateral info is stored in a struct/mapping pair
    struct collateral{
        address ERC20Contract;
        uint256 ammount;
    }
    mapping(uint256 => collateral) public collateralLookup;

    /**
    * @notice constructor just runs the ERC20PaymentStandard constructor
    * @param _bonds is the contract address of bonds
     */
    constructor(address _bonds) ERC20PaymentStandard(_bonds){}

    /**
    * @notice addCollateral must be called before issuing loan
    * @param _ERC20Contract address of the ERC20 you want to have as collaterall. DOES NOT have to be equal to payment ERC20
    * @param _ammount is the ammount to add as collateral
    * @param _loanId is the loan ID to add collateral to
     */
    function addCollateral(address _ERC20Contract, uint256 _ammount, uint256 _loanId) external{
        require(loanLookup[_loanId].borrower == msg.sender, "only the borrower can add collateral");
        require(collateralLookup[_loanId].ammount == 0, "Can only add collateral once");
        IERC20 erc20 = IERC20(_ERC20Contract);
        collateralLookup[_loanId] = collateral(_ERC20Contract, _ammount);
        erc20.transferFrom(msg.sender, address(this), _ammount);
    }

    /**
    * @notice return Collateral when the loan is complete 
    * @param _loanId is the loan ID
     */
    function returnCollateral(uint256 _loanId) external{
        require(msg.sender == loanLookup[_loanId].borrower, "only the borrower can collect collateral");
        require(isComplete(_loanId) || !loanLookup[_loanId].issued, "loan must be paid off or not started to collect collateral");
        IERC20 erc20 = IERC20(collateralLookup[_loanId].ERC20Contract);
        erc20.transfer(msg.sender, collateralLookup[_loanId].ammount);
    }

    /*
     * handles payment collection automatically when ERC1155s are sent. Overriden from ERC20PaymentStandard.sol
     */
    function onERC1155Received(address _operator, address _from, uint256 _id, uint256 _value, bytes calldata _data) public override returns(bytes4){
        require(loanLookup[_id].issued, "this loan has not been issued yet. How do you even have bonds for it???");
        require(_value <= loanLookup[_id].awaitingCollection,"There is not enough payments available for collection");
        IERC20 erc20 = IERC20(loanLookup[_id].ERC20Address);
        erc20.transfer(_from, _value);
        //Handle collaterall transfer (first come first serve) if delinquent 
        if(isDelinquent(_id) && collateralLookup[_id].ammount !=0){
            IERC20 col = IERC20(collateralLookup[_id].ERC20Contract);
            if(collateralLookup[_id].ammount < _value){
                col.transfer(_from, collateralLookup[_id].ammount);
            }else{
                col.transfer(_from, _value);
            }
        }
        return this.onERC1155Received.selector;
    }
}