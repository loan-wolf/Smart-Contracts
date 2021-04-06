const { assert, expect } = require("chai");
const timeMachine = require('ganache-time-traveler');
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
const paymentPeriod = 5;            //Seconds. Not miliseconds
const principalNum = 50;
const principal = tokens(principalNum.toString());
const interestRate = 0.12;              //Will be converted to inverse
const accrualPeriod = 10;              //Seconds. Not miliseconds
const collateral = tokens('100');

//Helper functions
function tokens(n){
    return web3.utils.toWei(n,"ether");
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
        await mockDai.transfer(borrower1, tokens('1000',{from:dev}));
        await mockDai.transfer(lender1,tokens('1000'),{from:dev});
        await mockDai.transfer(lender2,tokens('1000'),{from:dev});

    });

    describe('borrower configures bond', async() => {
        it('configureNew()', async()=>{
            await payment.configureNew(
                mockDai.address,
                borrower1,
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

        it('borrower adds DAI collateral', async()=>{
            await mockDai.approve(payment.address, collateral, {from:borrower1});
            await payment.addCollateral(mockDai.address, collateral, bondIDs[0],{from: borrower1});
            const col = await payment.collateralLookup(bondIDs[0]);
            assert.equal(col["ammount"], collateral);
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

    describe('Delinquent loan', async() =>{
        it('await payment period', async()=>{
            await timeMachine.advanceTimeAndBlock(paymentPeriod);
            assert(true);
        });
        
        it('loan is delinquent', async()=>{
            const delinquent = await payment.isDelinquent(bondIDs[0]);
            assert(delinquent);
        });

        it('Lender 1 collects collateral', async() =>{
            let balBefore = await mockDai.balanceOf(lender1);
            let nftBal = await bonds.balanceOf(lender1,bondIDs[0]);
            await bonds.setApprovalForAll(payment.address, true, {from:lender1});
            await payment.withdrawl(bondIDs[0],nftBal,{from:lender1});
            let balAfter = await mockDai.balanceOf(lender1);
            await bonds.setApprovalForAll(payment.address, false, {from:lender1});
            assert.equal((balBefore.add(new BN(nftBal))).toString(), balAfter.toString());
        });
    });



});