/// SPDX-License-Identifier: None
pragma solidity ^0.8.0;

//For Remix:
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC1155/ERC1155.sol";
//For Local:
//import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";

/**
* @title paymentContract
* @author Carson Case
*
* @dev interface for paymentContract
*As of right now, each payment contract can only have 1 address (borrower).
*And they can only mint identical NFTs. In the future I'd like to have the
*standard allow for shared use of the contracts as it can make things a
*lot more user friendly.
*
* @notice these are the REQUIRED functions of a pyament contract.
*More is possible and encouraged. But these are the only ways that the bonds
*contract will interact with them
 */
interface paymentContract {

    /// @dev used to define a new loans quantity of tokens to mint
    function principal() external view returns(uint256);

    /// @dev used to get accruances while staking
    function accrualPeriod() external view returns(uint256);
   
    /// @dev used to calculate interest when unstaking
    function interestRateInverse() external view returns(uint256);

    /// @dev used to check if borrower is calling a function
    function borrower() external view returns(address);

    /// @dev can only be called by bonds contract. Updates the total due
    function addInterest(uint256 _amm) external;

    /// @dev is used to make sure new loans can only be minted if actually new
    function isComplete() external returns(bool);
}


/**
* @title Bonds
* @author Carson Case
*
* @dev bellow are some notes on improvements
*   -figure out compound staking interest
*       *compare complexity/gas
*   -allow multiple users/loans per contract
*   -unstakeAmmount()
*   -Fix issue with unstakeAll not sending nfts but instead minting
*   -See if holding functions can be imported/interfaced
*   -Create interface for this contract. Seperate file
*   -Move metadata url to non magic variable
 */
contract Bonds is ERC1155 {
    
    //Data held per person to keep track of staking
    struct IOU{
        bool staking;
        uint256 ID;
        uint256 ammount;
        uint256 timeStaked;
    }
    
    //Staking info mapping
    mapping(address => IOU) public staking;
    
    //Constructor. Empty for now except the metadata url
    constructor() ERC1155("https://test.com/api/{id}.json"){
        
    }
    
    /**
    * @notice function creates the tokens for a new loan so they can be sold to generate funding
    * @param _paymentContractAddress is the address of the loan's contract. "Borrower" in this
    *must be the same as msg.sender
    * @return uint256 as the id of the ERC1155 token. This is for now, the uint160 representation 
    *of the payment contract's address. Typecasted to uint256
     */
    function newLoan(address _paymentContractAddress) external returns(uint256) {
        paymentContract pc = paymentContract(_paymentContractAddress);
        require(msg.sender == pc.borrower(), "Only the borrower of this contract can mint the bonds to it");
        require(!pc.isComplete(),"You must pay off your current loan before starting a new one");
        uint256 id = uint256(uint160(_paymentContractAddress));
        uint256 ammToMint = pc.principal();

        _mint(msg.sender, id, ammToMint, "");
        return(id);
    }
    
    /**
    * @notice function stakes an ammount of ERC-1155's with id from sender
    * @notice you need to approve this contract to spend your ERC-1155's first
    * @param _id is the token's id. Also the paymentcontract's uint256 representation
    * @param _amm is the ammount to stake
     */
    function stake(uint256 _id, uint256 _amm) external {
        safeTransferFrom(msg.sender, address(this), _id, _amm, "");
        staking[msg.sender] = IOU(
            true,
            _id,
            _amm,
            block.timestamp
        );
    }
    
    /**
    * @notice function calculates interest earned over time staking and mints that along with your staking balance
    * @notice the addInterest function (which only this contract can preform) also updates total ammount due to contract
     */
    function unstakeAll() external {
        require(staking[msg.sender].staking, "You are not staking any NFTs");
        uint256 id = staking[msg.sender].ID; 
        uint256 amm = staking[msg.sender].ammount;
        uint256 x = getAccruances(msg.sender);
        //Reset the staking for sender before calling any functions
        staking[msg.sender] = IOU(
            false,
            0,
            0,
            0
        );
        //Call the payment contract before minting or transfering any tokens
        paymentContract pc = paymentContract(address(uint160(id)));
        uint256 toMint = x * (amm / pc.interestRateInverse());
        //Update the balance with new interest
        pc.addInterest(toMint);
        //safeTransferFrom(address(this), msg.sender, id, amm, ""); This causes an issue. It thinks itself is not approved. Just going to mint for now
        _mint(msg.sender, id, toMint+amm, "");
        
    }
    
    /**
    * @notice function get's how many accruance periods a person has staked through
    * @param _who is who to check
    * @return the number of periods
     */
    function getAccruances(address _who) internal view returns(uint256) {
        IOU memory iou = staking[_who];
        require(iou.staking,"You are not staking any NFTs");
        uint256 accrualPeriod = paymentContract(address(uint160(iou.ID))).accrualPeriod();
        return((block.timestamp - iou.timeStaked)/accrualPeriod);
    }
    
    //Functions to receive ERC1155. Since I can't make it a ERC1155Holder with dependancy colission
    function onERC1155Received(address, address, uint256, uint256, bytes memory) public virtual returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(address, address, uint256[] memory, uint256[] memory, bytes memory) public virtual returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }
    
    
}