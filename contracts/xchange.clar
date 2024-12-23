;; xChange Bridge Contract
;; Handles cross-chain swaps between Bitcoin and Stacks

(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u1))
(define-constant ERR_INSUFFICIENT_BALANCE (err u2))
(define-constant ERR_INVALID_SWAP (err u3))

;; Data maps for storing swap information and balances
(define-map balances principal uint)
(define-map pending-swaps uint 
    { initiator: principal,
      amount: uint,
      recipient-btc: (buff 128)
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

;; Deposit STX tokens into the bridge
(define-public (deposit-stx (amount uint))
    (begin
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        (map-set balances tx-sender 
            (+ (default-to u0 (map-get? balances tx-sender)) amount)
        )
        (ok true)
    )
)

;; Initiate a swap to Bitcoin
(define-public (initiate-swap (amount uint) (recipient-btc (buff 128)))
    (let (
        (sender-balance (default-to u0 (map-get? balances tx-sender)))
        (swap-id (+ (var-get last-swap-id) u1))
    )
        (asserts! (>= sender-balance amount) ERR_INSUFFICIENT_BALANCE)
        (asserts! (> amount u0) ERR_INVALID_SWAP)
        
        ;; Update sender balance
        (map-set balances tx-sender (- sender-balance amount))
        
        ;; Record the pending swap
        (map-set pending-swaps 
            swap-id
            { initiator: tx-sender,
              amount: amount,
              recipient-btc: recipient-btc
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
        (asserts! (is-some (map-get? pending-swaps swap-id)) ERR_INVALID_SWAP)
        (map-delete pending-swaps swap-id)
        (ok true)
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
        (swap (unwrap! (get-pending-swap swap-id) ERR_INVALID_SWAP))
    )
        ;; Verify the caller is the swap initiator
        (asserts! (is-eq tx-sender (get initiator swap)) ERR_NOT_AUTHORIZED)
        
        ;; Return the funds to the initiator
        (map-set balances tx-sender 
            (+ (default-to u0 (map-get? balances tx-sender)) (get amount swap))
        )
        
        ;; Remove the pending swap
        (map-delete pending-swaps swap-id)
        (ok true)
    )
)

;; Emergency withdrawal function (admin only)
(define-public (emergency-withdraw (amount uint) (recipient principal))
    (begin
        ;; Only contract owner can call this function
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
        
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

;; Constants for batch swaps and expiration
(define-constant MAX_BATCH_SIZE u10)
(define-constant SWAP_EXPIRATION_BLOCKS u144) ;; approximately 24 hours in blocks
(define-constant ERR_BATCH_TOO_LARGE (err u4))
(define-constant ERR_SWAP_EXPIRED (err u5))

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
        ;; Check total balance
        (asserts! (>= sender-balance total-amount) ERR_INSUFFICIENT_BALANCE)
        
        ;; Process each swap
        (map-set balances tx-sender (- sender-balance total-amount))
        
        ;; Create all swaps
        (let ((swap-ids (map create-single-swap amounts recipients)))
            (ok swap-ids)
        )
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
              recipient-btc: recipient-btc
            }
        )
        swap-id
    )
)

;; Function to expire and refund old swaps
(define-public (expire-swap (swap-id uint))
    (let (
        (swap (unwrap! (get-pending-swap swap-id) ERR_INVALID_SWAP))
        (current-block block-height)
        (initiator (get initiator swap))
        (swap-amount (get amount swap))
    )
        ;; Check if swap is old enough to expire
        (asserts! (>= current-block (+ SWAP_EXPIRATION_BLOCKS u144)) ERR_SWAP_EXPIRED)
        
        ;; Return funds to initiator
        (map-set balances initiator 
            (+ (default-to u0 (map-get? balances initiator)) swap-amount)
        )
        
        ;; Remove expired swap
        (map-delete pending-swaps swap-id)
        (ok true)
    )
)