const { assert, expect } = require("chai");
require("chai")
    .use(require("chai-as-promised"))
    .should();

const BN = require('bn.js');

//Contracts
const Bonds = artifacts.require("Bonds");
const Payment = artifacts.require("ERC20CollateralPayment");
const MockDai = artifacts.require("MockDai");

//Function test values
const DAI_suppy = tokens('10000');
const min_payment = tokens('20');
const paymentPeriod = 12000;            //Seconds. Not miliseconds
const principalNum = 50;
const principal = tokens(principalNum.toString());
const interestRate = 0.12;              //Will be converted to inverse
const accrualPeriod = 10;              //Seconds. Not miliseconds
const staking = true;                  //if true then wait the time for staking to test it
//Helper functions
function tokens(n){
    return web3.utils.toWei(n,"ether");
}

function wait(time){
    return new Promise(resolve => setTimeout(resolve, time));
}

let bonds, payment, mockDai;
let bondIDs = [];
//Bonds contract tests
contract(Bonds, async([dev,borrower1,lender1, lender2, hacker]) => {

    before(async()=>{
        bonds = await Bonds.new({from:dev});
        payment = await Payment.new(
            bonds.address,
            {from: dev}
        );
        mockDai = await MockDai.new(DAI_suppy,{from:dev});
    });

    describe('Bonds Deployment', async() => {
        it('Has a URI', async() => {
            const uri = await bonds.uri(0);
            assert.equal("https://test.com/api/{id}.json",uri);
        });
    });

    describe('Mock Dai Deployment', async() => {
        it('Gave devFee', async() =>{
            const bal = await mockDai.balanceOf(dev);
            assert.equal(DAI_suppy, bal);
        });

        it('Dev sends 100 to each lender', async() =>{

            await mockDai.transfer(lender1,tokens('100'),{from:dev});
            await mockDai.transfer(lender2,tokens('100'),{from:dev});
        });

        it('Also dev sends 1000 to borrower so he can pay interest and collateral', async() =>{
            await mockDai.transfer(borrower1, tokens('1000',{from:dev}));
        });
    });
    

    describe('Payment Contract Deployment', async() =>{
        it('Recorded bond contract correctly', async()=>{
            const bondAddress = await payment.bondContract();
            assert.equal(bonds.address,bondAddress);
        });
        //Could test for each state variable here. But I'm not doing that. If the two above work the others likely do too
    });

    describe('Loan configuration', async() => {
        it('configure loan', async()=>{
            await payment.configureNew(
                mockDai.address,
                min_payment,
                paymentPeriod,
                principal,
                Math.floor(100 / (interestRate * 100)),
                accrualPeriod,
                {from: borrower1}
                );
            bondIDs[0] = await payment.loanIDs(borrower1, 0);
            assert(bondIDs[0]);
        });
    });

    describe('Collateral', async() => {
        it('borrower adds 100 DAI tokens of collateral', async()=>{
            await mockDai.approve(payment.address, tokens('100'), {from:borrower1});
            await payment.addCollateral(mockDai.address, tokens('100'), bondIDs[0],{from: borrower1});
            const col = await payment.collateralLookup(bondIDs[0]);
            assert.equal(col["ammount"], tokens('100'));
        });
    })
    
    
    describe('Bond creation', async() => {
        it('Hacker fails to create bonds for himself', async()=>{
            try {
                await bonds.newLoan(payment.address,bondIDs[0],{from:hacker});
                assert.fail();
            } catch (error) {
                assert.exists(error);
            }
            
        });

        it('Borrower creates bonds for himself with quantity equal to principal', async()=>{
            await bonds.newLoan(payment.address, bondIDs[0], {from:borrower1});
            const loan = await payment.loanLookup.call(bondIDs[0]);
            const bondBalanceActual = await bonds.balanceOf(borrower1, bondIDs[0]);
            assert.equal(loan["principal"].toString(), bondBalanceActual.toString());
        });
    });

    describe('Bond sale to lenders', async() => {
        //Assume hacker cannot send bonds. As openzeppelin takes care of this. I'd hope they'd test their ERC-1155 contract
        it('Lender1 is sent half the bonds and lender 2 the other half', async() => {
            await bonds.safeTransferFrom(borrower1, lender1, bondIDs[0], tokens((principalNum/2).toString()), web3.utils.asciiToHex(""),{from:borrower1});
            await bonds.safeTransferFrom(borrower1, lender2, bondIDs[0], tokens((principalNum/2).toString()), web3.utils.asciiToHex(""),{from:borrower1});
        });

        it('Borrower gets a matching ammount of mock Dai from the lenders', async() =>{
            const borrowerBalBefore = await mockDai.balanceOf(borrower1);
            await mockDai.transfer(borrower1,tokens((principalNum/2).toString()),{from: lender1});
            await mockDai.transfer(borrower1,tokens((principalNum/2).toString()),{from: lender2});
            const borrowerBalAfter = await mockDai.balanceOf(borrower1);
            assert.equal(principal.toString(), (borrowerBalAfter.sub(borrowerBalBefore)).toString());
        });

    });

    describe('Staking', async() => {
        if(staking){
        it('Lender1 stakes his whole balance of bonds', async()=>{
            const half = tokens((principalNum/2).toString());
            await bonds.safeTransferFrom(lender1, bonds.address, bondIDs[0], half, web3.utils.asciiToHex(""), {from: lender1});
            const stakingBal = await bonds.staking(lender1,1);
            assert.equal(stakingBal["value"]["ammount"], half);
        });

        it('Check and print accruances', async()=>{
            const a = await bonds.getAccruances(lender1, 1,{from:dev});
        });

        it('Wait for interest acruall seconds', async() => {
            await wait(1000*accrualPeriod);
            assert(true);
        });

        it('Lender1 unstakes to have his interest', async()=>{
            const prevBal = tokens((principalNum/2).toString());
            await bonds.unstake(1,{from:lender1});
            const bal = await bonds.balanceOf(lender1, bondIDs[0]);
            let a = new BN(prevBal);
            let b = new BN(bal);
            assert.equal(a.cmp(b), -1);
        });
    }

    });

    describe('Payments', async() => {
        it('borrower makes minimum payment', async()=>{
            await mockDai.approve(payment.address, min_payment, {from: borrower1});
            await payment.payment(bondIDs[0], min_payment,{from: borrower1});
            const loan = await payment.loanLookup.call(bondIDs[0]);
            assert.equal(min_payment,loan["paymentComplete"]);
        });

        it('Hacker cant take the money', async()=>{
            try {
                await bonds.safeTransferFrom(hacker,payment.address,bondIDs[0],tokens('100'), web3.utils.asciiToHex(""),{from: hacker});
                assert.fail();
            } catch (error) {
                assert.exists(error);
            }
        });
        
        //is ok to fail for now
        it('Lender1 takes payment', async()=>{
            let balBefore = await mockDai.balanceOf(lender1);
            await bonds.safeTransferFrom(lender1, payment.address, bondIDs[0],min_payment, web3.utils.asciiToHex(""), {from:lender1});
            let balAfter = await mockDai.balanceOf(lender1);
            balBefore = new BN(balBefore);
            balAfter = new BN(balAfter);
            assert.equal((balBefore.add(new BN(min_payment))).toString(), balAfter.toString());
        });

        it('Borrower finishes payment', async()=>{
            const obj = await payment.loanLookup.call(bondIDs[0]);
            const total = obj["totalPaymentsValue"];
            const complete = await obj["paymentComplete"];
            const toPay = total.sub(complete);
            await mockDai.approve(payment.address, toPay, {from: borrower1});
            await payment.payment(bondIDs[0],toPay,{from: borrower1});
            const isComplete = await payment.isComplete(bondIDs[0]);
            assert(isComplete);
        });

        it('Lender2 collects the rest', async()=>{    
            
            const nftbal = await bonds.balanceOf(lender2,bondIDs[0]);
            const daibalpre = await mockDai.balanceOf(lender2);
            await bonds.safeTransferFrom(lender2,payment.address,bondIDs[0],nftbal, web3.utils.asciiToHex(""), {from:lender2});
            const bal = await mockDai.balanceOf(lender2);
            //Is 1 when second value is larger. It should be slightly because gas fees
            assert.equal((bal.sub(daibalpre)).toString(), nftbal.toString());
        });
    });

    describe('Wrapping up', async() => {
        it('Borrower collects 100 DAI collateral back', async()=>{
            const balBefore = await mockDai.balanceOf(borrower1);
            await payment.returnCollateral(bondIDs[0],{from:borrower1});
            const balAfter = await mockDai.balanceOf(borrower1);
            assert.equal(balBefore.toString(),balAfter.sub(new BN(tokens('100'))).toString());
        })
    })
    
    
    
})