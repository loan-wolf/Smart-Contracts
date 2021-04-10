/// SPDX-License-Identifier: None
pragma solidity ^0.8.0;

import './ERC20PaymentStandard.sol';

/**
* @title AaveLendingPool 
* @notice Is the lending pool contract for aave used to get aave's lending rate for a given token
* @author Carson Case
 */
interface AaveLendingPool{
    struct ReserveData {
        //stores the reserve configuration
        ReserveConfigurationMap configuration;
        //the liquidity index. Expressed in ray
        uint128 liquidityIndex;
        //variable borrow index. Expressed in ray
        uint128 variableBorrowIndex;
        //the current supply rate. Expressed in ray
        uint128 currentLiquidityRate;
        //the current variable borrow rate. Expressed in ray
        uint128 currentVariableBorrowRate;
        //the current stable borrow rate. Expressed in ray
        uint128 currentStableBorrowRate;
        uint40 lastUpdateTimestamp;
        //tokens addresses
        address aTokenAddress;
        address stableDebtTokenAddress;
        address variableDebtTokenAddress;
        //address of the interest rate strategy
        address interestRateStrategyAddress;
        //the id of the reserve. Represents the position in the list of the active reserves
        uint8 id;
    }

    struct ReserveConfigurationMap {
        //bit 0-15: LTV
        //bit 16-31: Liq. threshold
        //bit 32-47: Liq. bonus
        //bit 48-55: Decimals
        //bit 56: Reserve is active
        //bit 57: reserve is frozen
        //bit 58: borrowing is enabled
        //bit 59: stable rate borrowing enabled
        //bit 60-63: reserved
        //bit 64-79: reserve factor
        uint256 data;
     }

    function getReserveData(address)
    external
    view
    returns (ReserveData memory);
}

/**
* @title PaymentAAveWrappedAPY
* @notice Is an example of a contract based on the ERC20 Payment Standard that matches AAve's borrow rate for the payment token anytime interest is collected
* @notice NOTE. The interest rate found in the loan struct is NOT accurate. The getInterest function must be used with this contract.
* @author Carson Case
 */
contract PaymentAAveWrappedAPY is ERC20PaymentStandard{
    uint8 constant PERCENT_PRECISION = 27;
    uint128 constant SECONDS_IN_A_YEAR = 31540000;
    address public aaveContract;
    
    /// @notice constructor takes in AAve lending pool address
    constructor(address _bondsContract, address _aaveContract) ERC20PaymentStandard(_bondsContract){
        //0xE0fBa4Fc209b4948668006B2bE61711b7f465bAe;
        aaveContract = _aaveContract;
    }
    
    /**
    * @notice contract must be configured before bonds are issued. Pushes new loan to array for user
    * @dev borrower is msg.sender for testing. In production might want to make this a param
    * @param _erc20 is the ERC20 contract address that will be used for payments
    * @param _borrower is the borrower loan is being configured for. Keep in mind. ONLY this borrower can mint bonds to start the loan
    * @param _minPayment is the minimum payment that must be made before the payment period ends
    * @param _paymentPeriod payment must be made by this time or delinquent function will return true
    * @param _principal the origional loan value before interest
    * @param _inverseInterestRate What you put does not matter. Will always be based on aave.
    * @param _accrualPeriod What you put does not matter. It will be 1 second since it is 1 second for aave.
    * @return the id it just created
     */
    function configureNew(
    address _erc20,
    address _borrower,
    uint256 _minPayment, 
    uint256 _paymentPeriod, 
    uint256 _principal, 
    uint256 _inverseInterestRate, 
    uint256 _accrualPeriod
    )
    external
    override
    returns(uint256)
    {
        require(getAPY(_erc20) != 0, "This token is not compatable with AAVe. Please use a different payment contract");
        //Create new ID for the loan
        uint256 id = getId(_borrower, loanIDs[_borrower].length);
        //Push to loan IDs
        loanIDs[_borrower].push(id);
        //Add loan info to lookup
        loanLookup[id] = loan(
        {
            issued: false,
            ERC20Address: _erc20,
            borrower: msg.sender,
            merkleRoot: keccak256("Hello World"),
            paymentPeriod: _paymentPeriod,
            paymentDueDate: block.timestamp + _paymentPeriod,
            minPayment: _minPayment,
            interestRateInverse: _inverseInterestRate,
            accrualPeriod: 1,
            principal: _principal,
            totalPaymentsValue: _principal,               //For now. Will update with interest updates
            awaitingCollection: 0,
            paymentComplete: 0
            }
        );
        return id;
    }
    
    /**
    * @notice get the interest rate of a loan. Makes it easy for other contract since it doens't have to parse struct
    * @param _id is the loan ID
    * @return inverse interest rate
     */
    function getInterest(uint256 _id) external virtual override view returns(uint256){
        return(convertInterestToInverse(getAPY(loanLookup[_id].ERC20Address)));
    }

    /**
    * @notice function gets the APY from AAve's contract
    * @param _token is the erc20 to get the aave borrow rate for
    * @return uint258 as the rate
     */
    function getAPY(address _token) internal virtual view returns(uint128){
        AaveLendingPool alp = AaveLendingPool(aaveContract);
        return alp.getReserveData(_token).currentVariableBorrowRate;
    }
    
    /**
    * @notice function converts the 27 decimal precision percent from aave to a inverse
    * @param _interestInPercent is the 27 decimal precision precent
    * @return a uint256 of the lending rate in an inverse
     */
    function convertInterestToInverse(uint128 _interestInPercent) internal virtual pure returns(uint256){
        uint256 numerator = 10**PERCENT_PRECISION;
        return((numerator*SECONDS_IN_A_YEAR)/_interestInPercent);
    }
    
}

