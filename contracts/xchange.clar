;; xChange Bridge Contract
;; Handles cross-chain swaps between Bitcoin and Stacks

(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u1))
(define-constant ERR_INSUFFICIENT_BALANCE (err u2))
(define-constant ERR_INVALID_SWAP (err u3))
(define-constant ERR_BATCH_TOO_LARGE (err u4))
(define-constant ERR_SWAP_EXPIRED (err u5))
(define-constant ERR_INVALID_AMOUNT (err u6))
(define-constant ERR_INVALID_RECIPIENT (err u7))
(define-constant ERR_SWAP_NOT_FOUND (err u8))
(define-constant MAX_BATCH_SIZE u10)
(define-constant SWAP_EXPIRATION_BLOCKS u144) ;; approximately 24 hours in blocks
(define-constant MIN_AMOUNT u1000) ;; Minimum amount to prevent dust attacks
(define-constant MAX_AMOUNT u1000000000) ;; Maximum amount to prevent overflow

;; Data maps for storing swap information and balances
(define-map balances principal uint)
(define-map pending-swaps uint 
    { initiator: principal,
      amount: uint,
      recipient-btc: (buff 128),
      created-at: uint
    }
)

(define-data-var last-swap-id uint u0)

;; Initialize contract
(define-public (initialize)
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        (ok true)
    )
)

;; Validate amount is within acceptable range
(define-private (validate-amount (amount uint))
    (and 
        (>= amount MIN_AMOUNT)
        (<= amount MAX_AMOUNT)
    )
)

;; Validate Bitcoin recipient address
(define-private (validate-btc-recipient (recipient-btc (buff 128)))
    (and 
        (not (is-eq recipient-btc 0x))
        (<= (len recipient-btc) u128)
    )
)

;; Safe addition with overflow check
(define-private (safe-add (a uint) (b uint))
    (if (>= (+ a b) a)
        (+ a b)
        u0  ;; Return 0 if overflow would occur
    )
)

;; Validate swap ID is within valid range
(define-private (validate-swap-id (swap-id uint))
    (and 
        (> swap-id u0)
        (<= swap-id (var-get last-swap-id))
    )
)

;; Validate swap exists and is active
(define-private (validate-swap (swap-id uint))
    (begin
        (asserts! (validate-swap-id swap-id) ERR_INVALID_SWAP)
        (match (map-get? pending-swaps swap-id)
            swap-data (ok swap-data)
            ERR_SWAP_NOT_FOUND
        )
    )
)

;; Deposit STX tokens into the bridge
(define-public (deposit-stx (amount uint))
    (begin
        (asserts! (validate-amount amount) ERR_INVALID_AMOUNT)
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        
        (let ((current-balance (default-to u0 (map-get? balances tx-sender)))
              (new-balance (safe-add current-balance amount)))
            (asserts! (> new-balance u0) ERR_INVALID_AMOUNT)
            (map-set balances tx-sender new-balance)
            (ok true)
        )
    )
)

;; Initiate a swap to Bitcoin
(define-public (initiate-swap (amount uint) (recipient-btc (buff 128)))
    (let (
        (sender-balance (default-to u0 (map-get? balances tx-sender)))
        (swap-id (+ (var-get last-swap-id) u1))
    )
        ;; Validate inputs
        (asserts! (validate-amount amount) ERR_INVALID_AMOUNT)
        (asserts! (validate-btc-recipient recipient-btc) ERR_INVALID_RECIPIENT)
        (asserts! (>= sender-balance amount) ERR_INSUFFICIENT_BALANCE)
        
        ;; Update sender balance
        (map-set balances tx-sender (- sender-balance amount))
        
        ;; Record the pending swap with current block height
        (map-set pending-swaps 
            swap-id
            { initiator: tx-sender,
              amount: amount,
              recipient-btc: recipient-btc,
              created-at: block-height
            }
        )
        
        ;; Update last swap ID
        (var-set last-swap-id swap-id)
        (ok swap-id)
    )
)

;; Complete a swap (admin only)
(define-public (complete-swap (swap-id uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        ;; Validate swap exists before attempting to complete it
        (asserts! (validate-swap-id swap-id) ERR_INVALID_SWAP)
        (let ((swap (try! (validate-swap swap-id))))
            ;; Double-check swap-id is still valid before deletion
            (asserts! (validate-swap-id swap-id) ERR_INVALID_SWAP)
            (map-delete pending-swaps swap-id)
            (ok true)
        )
    )
)

;; Get pending swap details
(define-read-only (get-pending-swap (swap-id uint))
    (map-get? pending-swaps swap-id)
)

;; Get user balance
(define-read-only (get-balance (user principal))
    (default-to u0 (map-get? balances user))
)

;; Cancel a pending swap (can only be done by the initiator)
(define-public (cancel-swap (swap-id uint))
    (let (
        (swap (try! (validate-swap swap-id)))
    )
        ;; Verify the caller is the swap initiator
        (asserts! (is-eq tx-sender (get initiator swap)) ERR_NOT_AUTHORIZED)
        
        ;; Return the funds to the initiator
        (let ((current-balance (default-to u0 (map-get? balances tx-sender)))
              (new-balance (safe-add current-balance (get amount swap))))
            (asserts! (> new-balance u0) ERR_INVALID_AMOUNT)
            (map-set balances tx-sender new-balance)
            
            ;; Remove the pending swap
            (map-delete pending-swaps swap-id)
            (ok true)
        )
    )
)

;; Emergency withdrawal function (admin only)
(define-public (emergency-withdraw (amount uint) (recipient principal))
    (begin
        ;; Only contract owner can call this function
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        (asserts! (validate-amount amount) ERR_INVALID_AMOUNT)
        ;; Verify recipient is not null principal
        (asserts! (not (is-eq recipient 'SP000000000000000000002Q6VF78)) ERR_INVALID_RECIPIENT)
        
        ;; Verify contract has sufficient balance
        (let (
            (contract-balance (stx-get-balance (as-contract tx-sender)))
        )
            (asserts! (>= contract-balance amount) ERR_INSUFFICIENT_BALANCE)
            
            ;; Transfer funds to the specified recipient
            (try! (as-contract (stx-transfer? amount tx-sender recipient)))
            (ok true)
        )
    )
)

;; Batch swap function - process multiple swaps in one transaction
(define-public (batch-swap (amounts (list 10 uint)) (recipients (list 10 (buff 128))))
    (let (
        (amounts-len (len amounts))
        (recipients-len (len recipients))
        (total-amount (fold + amounts u0))
        (sender-balance (default-to u0 (map-get? balances tx-sender)))
    )
        ;; Verify lists are same length and not too large
        (asserts! (and (<= amounts-len MAX_BATCH_SIZE) 
                      (is-eq amounts-len recipients-len)) ERR_BATCH_TOO_LARGE)
        
        ;; Validate all amounts and recipients
        (asserts! (fold and (map validate-amount amounts) true) ERR_INVALID_AMOUNT)
        (asserts! (fold and (map validate-btc-recipient recipients) true) ERR_INVALID_RECIPIENT)
        
        ;; Check total balance
        (asserts! (>= sender-balance total-amount) ERR_INSUFFICIENT_BALANCE)
        
        ;; Process each swap
        (map-set balances tx-sender (- sender-balance total-amount))
        
        ;; Create all swaps
        (ok (map create-single-swap amounts recipients))
    )
)

;; Helper function to create a single swap within batch-swap
(define-private (create-single-swap (amount uint) (recipient-btc (buff 128)))
    (let (
        (swap-id (+ (var-get last-swap-id) u1))
    )
        (var-set last-swap-id swap-id)
        (map-set pending-swaps 
            swap-id
            { initiator: tx-sender,
              amount: amount,
              recipient-btc: recipient-btc,
              created-at: block-height
            }
        )
        swap-id
    )
)

;; Function to expire and refund old swaps
(define-public (expire-swap (swap-id uint))
    (let (
        (swap (try! (validate-swap swap-id)))
        (current-block block-height)
        (initiator (get initiator swap))
        (swap-amount (get amount swap))
        (created-at (get created-at swap))
    )
        ;; Check if swap is old enough to expire
        (asserts! (>= (- current-block created-at) SWAP_EXPIRATION_BLOCKS) ERR_SWAP_EXPIRED)
        
        ;; Return funds to initiator
        (let ((current-balance (default-to u0 (map-get? balances initiator)))
              (new-balance (safe-add current-balance swap-amount)))
            (asserts! (> new-balance u0) ERR_INVALID_AMOUNT)
            (map-set balances initiator new-balance)
            
            ;; Remove expired swap
            (map-delete pending-swaps swap-id)
            (ok true)
        )
    )
)