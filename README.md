# xChange: Secure Cross-Chain Bridge Interface

xChange is a decentralized bridge interface that enables secure and verifiable asset transfers between Bitcoin and the Stacks blockchain. Built with robust Clarity smart contracts, the platform implements atomic swaps with comprehensive safety measures, expiration mechanisms, and multi-level validation checks.

## Key Features

- Secure atomic swaps between Bitcoin and Stacks blockchains
- Batch processing capabilities for multiple swaps
- Built-in safety mechanisms including:
  - Amount validation to prevent dust attacks
  - Swap expiration system
  - Emergency withdrawal functionality
  - Overflow protection
- Real-time transaction status monitoring
- User balance management system
- Comprehensive swap validation and verification

## Smart Contract Architecture

The core smart contract implements the following key functions:

### User Operations
- `deposit-stx`: Deposit STX tokens into the bridge with amount validation
- `initiate-swap`: Start a new cross-chain swap with recipient validation
- `cancel-swap`: Cancel a pending swap (initiator only)
- `batch-swap`: Process multiple swaps in a single transaction
- `get-pending-swap`: Retrieve details of pending swaps
- `get-balance`: Check user balances in the contract

### Administrative Functions
- `complete-swap`: Finalize verified swaps (admin only)
- `emergency-withdraw`: Emergency fund recovery system (admin only)
- `expire-swap`: Process expired swaps and return funds

### Safety Features
- Minimum and maximum amount constraints
- Expiration timelock (24-hour block window)
- Batch size limitations
- Comprehensive input validation
- Safe arithmetic operations

## Prerequisites

- [Stacks Wallet](https://www.hiro.so/wallet)
- [Clarity CLI](https://docs.stacks.co/references/claritycli) version 2.0 or higher
- Node.js v16 or higher
- Bitcoin node (optional for running a full node)

## Installation

1. Clone the repository:
```bash
git clone https://github.com/FineNK/xchange.git
cd xchange
```

2. Install dependencies:
```bash
npm install
```

3. Configure environment variables:
```bash
cp .env.example .env
# Edit .env with your configuration:
# - NETWORK=mainnet|testnet
# - CONTRACT_ADDRESS=<your_deployed_contract>
# - OWNER_ADDRESS=<contract_owner>
```

## Smart Contract Deployment

1. Build and check the contract:
```bash
clarity-cli check contracts/xchange.clar
clarity-cli build contracts/xchange.clar
```

2. Deploy to testnet:
```bash
clarinet deploy --testnet --network testnet
```

3. Deploy to mainnet (requires authorization):
```bash
clarinet deploy --mainnet --network mainnet
```

## Usage Guide

### Initiating a Single Swap

1. Connect your Stacks wallet
2. Deposit STX tokens using `deposit-stx`
3. Call `initiate-swap` with:
   - Amount (must be between MIN_AMOUNT and MAX_AMOUNT)
   - Bitcoin recipient address (validated format)
4. Monitor swap status through `get-pending-swap`

### Batch Swap Processing

1. Prepare arrays of:
   - Amounts (up to 10 swaps)
   - Recipient addresses
2. Call `batch-swap` with prepared arrays
3. Monitor individual swap statuses

### Swap Management

- Cancel pending swaps using `cancel-swap`
- Monitor expiration time (144 blocks ≈ 24 hours)
- Check balances with `get-balance`
- Expired swaps can be processed using `expire-swap`

## Security Considerations

The contract implements multiple security measures:

- Input validation for all public functions
- Amount bounds checking to prevent dust attacks
- Safe arithmetic operations to prevent overflow
- Timelock mechanisms for swap expiration
- Admin-only functions for critical operations
- Multi-level swap validation system
- Balance verification before operations

## Development

### Local Testing Environment

1. Start local development:
```bash
npm run dev
```

2. Run the test suite:
```bash
npm test
```

### Testing Framework

Comprehensive test suites covering:

- Contract function unit tests
- Input validation scenarios
- Error handling cases
- Integration tests
- Security test cases
- Batch processing verification

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/enhancement`)
3. Commit your changes (`git commit -m 'Add enhancement'`)
4. Push to the branch (`git push origin feature/enhancement`)
5. Open a Pull Request

### Development Guidelines

- Follow Clarity best practices
- Add tests for new features
- Update documentation
- Maintain security measures
- Test on testnet before mainnet deployment

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- Stacks Foundation for blockchain infrastructure
- Bitcoin Core developers
- Open source contributors
- Clarity language developers

## Security Audits

- Contract audit pending
- Regular security reviews planned
- Vulnerability reporting system in place



