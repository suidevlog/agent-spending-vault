import { SuiGrpcClient } from '@mysten/sui/grpc';

export const client = new SuiGrpcClient({
  network: 'testnet',
  baseUrl: 'https://fullnode.testnet.sui.io:443',
});