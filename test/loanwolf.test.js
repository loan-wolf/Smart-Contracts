const { assert, expect } = require("chai");
require("chai")
    .use(require("chai-as-promised"))
    .should();

const BN = require('bn.js');

//Contracts
const Bonds = artifacts.require("Bonds");
const SimpleEthPayment = artifacts.require("SimpleEthPayment");

//Function test values
const min_payment = tokens('20');
const paymentPeriod = 12000;            //Seconds. Not miliseconds
const principalNum = 50;
const principal = tokens(principalNum.toString());
const interestRate = 0.12;              //Will be converted to inverse
const accrualPeriod = 10;              //Seconds. Not miliseconds
//Helper functions
function tokens(n){
    return web3.utils.toWei(n,"ether");
}

function wait(time){
    return new Promise(resolve => setTimeout(resolve, time));
}

let bonds, simpleEthPayment;
let bondIDs = [];
//Bonds contract tests
contract(Bonds, async([dev,borrower1,lender1, lender2, hacker]) => {

    before(async()=>{
        bonds = await Bonds.new({from:dev});
        simpleEthPayment = await SimpleEthPayment.new(
            bonds.address,
            min_payment,
            paymentPeriod,
            principal,
            Math.floor(100/(interestRate*100)),               //No decimal inverse of interest rate
            accrualPeriod,
            {from: borrower1}
        );
    });

    describe('Bonds Deployment', async() => {
        it('Has a URI', async() => {
            const uri = await bonds.uri(0);
            assert.equal("https://test.com/api/{id}.json",uri);
        });
    });

    describe('Payment Contract Deployment', async() =>{
        it('Recorded borrower correctly', async()=>{
            const borrower = await simpleEthPayment.borrower();
            assert.equal(borrower1,borrower);
        });

        it('Recorded bonds contract correctly', async()=>{
            const contract = await simpleEthPayment.bondContract();
            assert.equal(bonds.address,contract); 
        });

        //Could test for each state variable here. But I'm not doing that. If the two above work the others likely do too
    });

    describe('Bond creation', async() => {
        it('Hacker fails to create bonds for himself', async()=>{
            try {
                await bonds.newLoan(simpleEthPayment.address,{from:hacker});
                assert.fail();
            } catch (error) {
                assert.exists(error);
            }
            
        });

        it('Borrower creates bonds for himself with quantity equal to principal', async()=>{
            const id = await bonds.newLoan(simpleEthPayment.address,{from:borrower1});
            bondIDs[0] = id.logs[0].args.id;
            const bondBalanceExpected = await simpleEthPayment.principal();
            const bondBalanceActual = await bonds.balanceOf(borrower1, bondIDs[0]);
            assert.equal(bondBalanceExpected.toString(), bondBalanceActual.toString());
        });
    });

    describe('Bond sale to lenders', async() => {
        //Assume hacker cannot send bonds. As openzeppelin takes care of this. I'd hope they'd test their ERC-1155 contract
        it('Lender1 is sent half the bonds and lender 2 the other half', async() => {
            await bonds.safeTransferFrom(borrower1, lender1, bondIDs[0], tokens((principalNum/2).toString()), web3.utils.asciiToHex(""),{from:borrower1});
            await bonds.safeTransferFrom(borrower1, lender2, bondIDs[0], tokens((principalNum/2).toString()), web3.utils.asciiToHex(""),{from:borrower1});
        });
    });

    describe('Staking', async() => {
        it('Lender1 stakes his whole balance of bonds', async()=>{
            const half = tokens((principalNum/2).toString());
            await bonds.stake(bondIDs[0],half,{from:lender1});
            const stakingBal = await bonds.staking(lender1);
            assert.equal(stakingBal.ammount.toString(), half.toString());
        });

        it('Wait for interest acruall seconds', async() => {
            await wait(1000*accrualPeriod);
            assert(true);
        });

        it('Lender1 unstakes to have his interest', async()=>{
            const prevBal = tokens((principalNum/2).toString());
            await bonds.unstakeAll({from:lender1});
            const bal = await bonds.balanceOf(lender1, bondIDs[0]);
            let a = new BN(prevBal);
            let b = new BN(bal);
            assert.equal(a.cmp(b), -1);
        });
    });
    
    describe('Payments', async() => {
        it('borrower makes minimum payment', async()=>{
            await simpleEthPayment.payment({value: min_payment, from: borrower1});
            const paymentComplete = await simpleEthPayment.paymentComplete();
            assert.equal(min_payment,paymentComplete);
        });

        it('Hacker cant take the money', async()=>{
            try {
                await bonds.setApprovalForAll(simpleEthPayment.address,true);
                await simpleEthPayment.collect(min_payment,{hacker});
                assert.fail();
            } catch (error) {
                assert.exists(error);
            }finally{
                await bonds.setApprovalForAll(simpleEthPayment.address,false);
            }
        });

        it('Lender1 takes payment', async()=>{
            const balBefore = await web3.eth.getBalance(lender1);
            await bonds.setApprovalForAll(simpleEthPayment.address,true,{from:lender1});
            await simpleEthPayment.collect(min_payment,{from:lender1});
            await bonds.setApprovalForAll(simpleEthPayment.address,false,{from:lender1});
            const balAfter = await web3.eth.getBalance(lender1);
            assert.equal(new BN(balBefore).cmp(new BN (balAfter)), -1);
        });

        it('Borrower finishes payment', async()=>{
            const total = await simpleEthPayment.totalPaymentsValue();
            const complete = await simpleEthPayment.paymentComplete();
            const toPay = total.sub(complete);
            await simpleEthPayment.payment({value: toPay, from: borrower1});
            const isComplete = await simpleEthPayment.isComplete();
            assert(isComplete);
        });

        it('Lender2 collects the rest', async()=>{    
            await bonds.setApprovalForAll(simpleEthPayment.address,true,{from:lender2});
            const nftbal = await bonds.balanceOf(lender2,bondIDs[0]);
            const ethbalpre = await web3.eth.getBalance(lender2);
            console.log(typeof(ethbalpre));
            await simpleEthPayment.collect(nftbal,{from:lender2});
            await bonds.setApprovalForAll(simpleEthPayment.address,false,{from:lender2});
            const bal = await web3.eth.getBalance(lender2);
            //Is 1 when second value is larger. It should be slightly because gas fees
            assert.equal((nftbal.add(new BN(ethbalpre))).cmp(new BN(bal.toString())), 1 );
        });
    });
    
    

})