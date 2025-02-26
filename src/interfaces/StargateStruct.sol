// StargateStruct.sol
pragma solidity ^0.8.0;


import {IStargateRouter} from "../interfaces/IStargateRouter.sol";
import {IStargateFactory} from "../interfaces/IStargateFactory.sol";

// Define a simple struct
struct StargateStruct {
    IStargateRouter STARGATE_COMPOSER;
    IStargateRouter STARGATE_RELAYER;
    IStargateFactory STARGATE_FACTORY;
}