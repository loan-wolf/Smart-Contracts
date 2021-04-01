/// SPDX-License-Identifier: None
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {IERC20PaymentStandard} from './IERC20PaymentStandard.sol';
/**
* @title Bonds
* @author Carson Case
* @notice Bonds mints ERC1155 tokens that represent ownership of a loan specified by a Payment Contract. These bonds can accrue interest and be exchanged for payments made in the payment contract
 */
contract Bonds is ERC1155 {
    
    //Stores ID-> payment contract relationships
    mapping(uint256 => address) public IDToContract;

    /// @notice A linked list is used to keep track of staking for each user. This is so we can delete (ustake) nodes in constant time while still being able to itterate easily
    /// @dev may one day use this in payment standard as well to itterate through loans per person.
    //Data held per person to keep track of staking
    struct IOU{
        bool staking;
        uint256 ID;
        uint256 ammount;
        uint256 timeStaked;
    }
    
    //Node for a linked list
    struct node{
        uint last;
        uint next;
        IOU value;
    }

    //In the linked list the head is always 0. Head actually represents null. There will never be a value stored there
    uint256 constant public head = 0;

    //Used to keep track of this info for each user's linked list of staking data
    mapping(address => uint256) public llTail;

    /// @notice this is the staking linked list. Access the node to find the next/last.The 0 node is the HEAD and cannot hold values. If HEAD points to
    /// itself then it's empty
    mapping(address => mapping(uint256 => node)) public staking;
    
    //Constructor. Empty for now except the metadata url
    constructor() ERC1155("https://test.com/api/{id}.json"){}
    
    /**
    * @notice function creates the tokens for a new loan so they can be sold to generate funding
    * @param _paymentContractAddress is the address of the loan's contract. "Borrower" in this
    * @param _id is the ID of the loan you;re minting
     */
    function newLoan(address _paymentContractAddress, uint256 _id) external{
        IERC20PaymentStandard pc = IERC20PaymentStandard(_paymentContractAddress);
        uint256 amm;
        address creator;
        (amm, creator) = pc.issueBonds(_id);
        require(msg.sender == creator, "Only the borrower of this contract can mint the bonds to it");
        IDToContract[_id] = _paymentContractAddress;
        _mint(creator, _id, amm, "");
    }
    
    /** 
    * @notice function unstakes bonds
    * @param _index is the index in the linked list mentioned above with state varaibles
    * @return if successful. May not be if loan has been completed since staking
     */
    function unstake(uint256 _index) external returns(bool){
        require(!_isEmpty(msg.sender), "You are not staking any NFTs");
        uint256 id = staking[msg.sender][_index].value.ID; 
        uint256 amm = staking[msg.sender][_index].value.ammount;
        uint256 x = getAccruances(msg.sender,_index);
        address paymentContract = IDToContract[id];
        //Reset the staking for sender before calling any functions
        
        //Remove staking from the ll
        _del(_index, msg.sender);
        //Call the payment contract before minting or transfering any tokens
        IERC20PaymentStandard pc = IERC20PaymentStandard(paymentContract);
        uint256 toMint = x * (amm / pc.getInterest(id));
        bool r;                 //Store return so we can call other contract before mint funciton. Don't want callback attacks
        //Update the balance with new interest. Store return value based on response.
        if(pc.addInterest(toMint, id)){
            r = true;
        }else{
            r = false;
        }
        //safeTransferFrom(address(this), msg.sender, id, amm, ""); This causes an issue. It thinks itself is not approved. Just going to mint for now
        _mint(msg.sender, id, toMint+amm, "");
        return r;
        
    }
    
    /**
    * @notice function get's how many accruance periods a person has staked through
    * @param _who is who to check
    * @param _index in the linked list
    * @return the number of periods
     */
    function getAccruances(address _who, uint256 _index) public view returns(uint256) {
        IOU memory iou = staking[_who][_index].value;
        require(iou.staking,"You are not staking any NFTs");
        address paymentContract = IDToContract[iou.ID];
        IERC20PaymentStandard pc = IERC20PaymentStandard(paymentContract);
        uint256 accrualPeriod = pc.getInterest(iou.ID);
        return((block.timestamp - iou.timeStaked)/accrualPeriod);
    }
    
    /**
    * @notice the function to hold an ERC1155. Coppied from @Openzeppelin. Only difference is here the function stakes any ERC-1155s sent to it
     */
    function onERC1155Received
        (
        address _operator,
        address _from,
        uint256 _id,
        uint256 _value,
        bytes calldata _data
        ) 
        public 
        returns(bytes4)
        {
            stake(_id,_value,_from);
            return this.onERC1155Received.selector;
    }

    /**
    * @notice Also a requirement coppied from @openzeppelin. Just handles batch staking
     */
    function onERC1155BatchReceived
        (
        address _operator, 
        address _from, 
        uint256[] memory _ids, 
        uint256[] memory _values, 
        bytes memory _data
        ) 
        public 
        virtual 
        returns (bytes4) 
            {
                require(_ids.length == _values.length, "_ids and _values must be the same length");
                for(uint i = 0; i<_ids.length; i++){
                    stake(_ids[i],_values[i],_from);
                }
            return this.onERC1155BatchReceived.selector;
    }


    /*=============================================================
    *LINKED LIST FUNCTIONS 
    *BELLOW 
    ==============================================================*/
    
    /**
    * @notice helper function
    * @param _who to lookup the linked list of
    * @return if ll is empty
     */
    function _isEmpty(address _who) private view returns(bool){
        return(staking[_who][head].next == 0);   
    }
    
    /** @notice push to tail of linkedList
    * @param _val is the value to insert at tail
    * @param _who is who to push in ll mapping
     */
    function _push(IOU memory _val, address _who) private{
        uint256 tail = llTail[_who];
        if(_isEmpty(_who)){
            staking[_who][head].next = 1;
            staking[_who][1] = node(0,0,_val);
            llTail[_who] = 1;
        }else{
            staking[_who][tail].next = tail+1;
            staking[_who][tail+1] = node(tail,0,_val);
            llTail[_who]++;
        }
    }
    
    /** @notice delete at a given index
    * @param _index is the pointer to the node
    * @param _who is who in ll mapping
     */
    function _del(uint256 _index, address _who) private{
        uint256 tail = llTail[_who];
        require(_index != head,"cannot delete the head");
        if(_index == tail){
            llTail[_who] = staking[_who][tail].last;
        }
        uint256 a = staking[_who][_index].last;
        uint256 b = staking[_who][_index].next;
        staking[_who][a].next = staking[_who][_index].next;
        staking[_who][b].last = staking[_who][_index].last;
        
        staking[msg.sender][_index].value = IOU(
            false,
            0,
            0,
            0
        );
        staking[msg.sender][_index].next = 0;
        staking[msg.sender][_index].last = 0;
        
    }
    /**
    * @notice function stakes an ammount of ERC-1155's with id from sender
    * @param _id is the token's id
    * @param _amm is the ammount to stake
    * @param _who is who to stake
     */
    function stake(uint256 _id, uint256 _amm, address _who) private {
        _push(IOU(
            true,
            _id,
            _amm,
            block.timestamp
        ),_who);
    }
}

