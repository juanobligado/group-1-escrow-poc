//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Useful for debugging. Remove when deploying to a live network.
import "forge-std/console.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

enum State { AWAITING_PAYMENT, AWAITING_DELIVERY, COMPLETE, REFUNDED }

contract MultiEscrow is ReentrancyGuard {
    struct Escrow {
        address payer;
        address payee;
        address arbiter;
        uint256 amount;
        State currentState;
    }

    mapping(uint256 => Escrow) public escrows;
    uint256 public escrowCount;

    event FundDeposited(uint256 indexed escrowId, address indexed payer, uint256 amount);
    event FundReleased(uint256 indexed escrowId, address indexed payee, uint256 amount);
    event FundRefunded(uint256 indexed escrowId, address indexed payer, uint256 amount);

    error InvalidState(State expected, State current);
    error IncorrectDepositAmount(uint256 expected, uint256 actual);

    modifier onlyPayer(uint256 escrowId) {
        require(msg.sender == escrows[escrowId].payer, "Payer Permission Required");
        _;
    }

    modifier onlyArbiter(uint256 escrowId) {
        require(msg.sender == escrows[escrowId].arbiter, "Arbiter Permission Required");
        _;
    }

    modifier inState(uint256 escrowId, State expectedState) {
        require(escrows[escrowId].currentState == expectedState, InvalidState(expectedState, escrows[escrowId].currentState));
        _;
    }

    function createEscrow(address _payee, address _arbiter, uint256 _amount) external returns (uint256) {
        escrowCount++;
        escrows[escrowCount] = Escrow({
            payer: msg.sender,
            payee: _payee,
            arbiter: _arbiter,
            amount: _amount,
            currentState: State.AWAITING_PAYMENT
        });
        return escrowCount;
    }

    function deposit(uint256 escrowId) external payable onlyPayer(escrowId) inState(escrowId, State.AWAITING_PAYMENT)  {
        if (msg.value != escrows[escrowId].amount) {
            revert IncorrectDepositAmount(escrows[escrowId].amount, msg.value);
        }
        escrows[escrowId].currentState = State.AWAITING_DELIVERY;
        emit FundDeposited(escrowId, msg.sender, msg.value);
    }

    function releaseFunds(uint256 escrowId) external onlyArbiter(escrowId) inState(escrowId, State.AWAITING_DELIVERY) nonReentrant {
        escrows[escrowId].currentState = State.COMPLETE;
        payable(escrows[escrowId].payee).transfer(escrows[escrowId].amount);
        emit FundReleased(escrowId, escrows[escrowId].payee, escrows[escrowId].amount);
    }

    function refund(uint256 escrowId) external onlyArbiter(escrowId) inState(escrowId, State.AWAITING_DELIVERY) nonReentrant {
        Escrow storage escrow = escrows[escrowId];
        uint256 amount = escrow.amount;
        escrow.currentState = State.REFUNDED;

        (bool success, ) = escrow.payer.call{value: amount}("");
        require(success, "Refund failed");

        emit FundRefunded(escrowId, escrow.payer, amount);
    }

}