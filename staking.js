// FUNCTIONS TO USE
// stake(uint256 _id, uint256 _amm) external
// unstake(uint256 _index) external returns(bool)
// getStakingAt(address _who, uint256 _index) external view returns(uint, uint, uint256, uint256, uint256)

const paymentInstance;

//Show current staking

const address;

//Iterate linked list. 
//Display is a function to display to screen
//When displaying keep track of i for when someone clicks a button on it to unstake
let i = await paymentInstance.getStakingAt(address, 0).call()
while(i[1] != 0){           //i[1] is the next pointer
display(i[2])       //ID
display(i[3])       //Ammount

i = await paymentInstance.getStakingAt(address, i).call()
}

//Call this when someone clicks unstake on a staking display
paymentInstance.unstake(i).send({from:address});

//Call this when someone stars staking
//Right now just stake all. Can later have them choose ammount to stake
let balance = await Bonds.balanceOf(address,LOAN_ID).call()
paymentInstance.stake(LOAN_ID, balance).send({from:address});

