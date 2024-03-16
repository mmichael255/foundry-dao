// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test,console} from "forge-std/Test.sol";
import {MyGovernor} from "../src/MyGovernor.sol";
import {Box} from "../src/Box.sol";
import {GovToken} from "../src/GovToken.sol";
import {TimeLock} from "../src/TimeLock.sol";

contract MyGorvernorTest is Test{
    MyGovernor governor;
    Box box;
    GovToken token;
    TimeLock timeLock;

    address public USER = makeAddr("user");
    uint256 public constant INITIAL_SUPPLY = 100 ether;
    uint256 public constant MIN_DELAY = 3600; //one hour
    uint256 public constant VOTING_DELAY = 10; 
    uint256 public constant VOTING_PERIOD = 50400; 

    address[] public proposers;
    address[] public executors;
    address[] public addressesToCall;
    uint256[] public values;
    bytes[] public callDatas;

    function setUp() public {
        token = new GovToken();
        token.mint(USER, INITIAL_SUPPLY);

        vm.startPrank(USER);
        token.delegate(USER);
        timeLock = new TimeLock(MIN_DELAY,proposers,executors);
        governor = new MyGovernor(token, timeLock);
        bytes32 proposerRole = timeLock.PROPOSER_ROLE();
        bytes32 executorRole = timeLock.EXECUTOR_ROLE();
        bytes32 adminRole = timeLock.DEFAULT_ADMIN_ROLE();

        timeLock.grantRole(proposerRole, address(governor));
        timeLock.grantRole(executorRole, address(0));
        timeLock.revokeRole(adminRole, msg.sender);
        box = new Box();
        box.transferOwnership(address(timeLock));
        vm.stopPrank();
    }

    function testCantUpdateBoxwithoutGovernance() public {
        vm.expectRevert();
        box.store(42);
    }

    function testGovernanceUpdatesBox() public {
        uint256 valueToStore = 42;
        string memory description = "store valu42 in box";
        values.push(0);
        addressesToCall.push(address(box));
        bytes memory callData = abi.encodeWithSignature("store(uint256)", valueToStore);
        callDatas.push(callData);
        
        //1.propose to DAO
        uint256 proposalId = governor.propose(addressesToCall, values, callDatas, description);

        console.log("proposalState", uint256(governor.state(proposalId)));

        vm.warp(block.timestamp + VOTING_DELAY + 1);
        vm.roll(block.number + VOTING_DELAY +1);
        console.log("proposalState", uint256(governor.state(proposalId)));
        
        string memory reason = "bueno";

        uint8 voteWay = 1;

        //2.vote
        vm.startPrank(USER);
        governor.castVoteWithReason(proposalId, voteWay, reason);
        vm.startPrank(USER);

        vm.warp(block.timestamp + VOTING_PERIOD + 1);
        vm.roll(block.number + VOTING_PERIOD + 1);

        //3.queue the TX
        bytes32 descriptionHash = keccak256(abi.encodePacked(description));
        governor.queue(addressesToCall, values, callDatas, descriptionHash);

        vm.warp(block.timestamp + MIN_DELAY + 1);
        vm.roll(block.number + MIN_DELAY + 1);

        //4.execute
        governor.execute(addressesToCall, values, callDatas, descriptionHash);

        assert(valueToStore == box.getNumber());
    }

}