;; Policy Issuance Contract
;; Manages insurance terms for different crops

;; Define data variables
(define-map crop-types
  { crop-id: uint }
  {
    name: (string-ascii 50),
    description: (string-ascii 200),
    base-premium-rate: uint,  ;; Rate per 1000 units of coverage (in cents)
    max-coverage-per-acre: uint  ;; Maximum coverage amount per acre (in cents)
  }
)

(define-map policies
  { policy-id: (string-ascii 36) }
  {
    farmer: principal,
    crop-id: uint,
    acres: uint,
    coverage-per-acre: uint,  ;; Coverage amount per acre (in cents)
    premium-amount: uint,     ;; Total premium amount (in cents)
    start-date: uint,         ;; Block height when policy starts
    end-date: uint,           ;; Block height when policy ends
    status: (string-ascii 20),;; active, expired, or claimed
    region-id: (string-ascii 10),
    premium-paid: bool
  }
)

(define-map policy-count-by-farmer
  { farmer: principal }
  { count: uint }
)

(define-map admins principal bool)

;; Define error codes
(define-constant ERR-NOT-AUTHORIZED u1)
(define-constant ERR-CROP-EXISTS u2)
(define-constant ERR-CROP-NOT-FOUND u3)
(define-constant ERR-POLICY-EXISTS u4)
(define-constant ERR-POLICY-NOT-FOUND u5)
(define-constant ERR-INVALID-PARAMETERS u6)
(define-constant ERR-PREMIUM-NOT-PAID u7)
(define-constant ERR-POLICY-EXPIRED u8)
(define-constant ERR-POLICY-NOT-ACTIVE u9)

;; Initialize contract with contract deployer as admin
(define-data-var contract-owner principal tx-sender)
(define-data-var next-crop-id uint u1)

;; Check if caller is an admin
(define-read-only (is-admin)
  (or
    (is-eq tx-sender (var-get contract-owner))
    (default-to false (map-get? admins tx-sender))
  )
)

;; Add a new admin
(define-public (add-admin (new-admin principal))
  (begin
    (asserts! (is-admin) (err ERR-NOT-AUTHORIZED))
    (ok (map-set admins new-admin true))
  )
)

;; Remove an admin
(define-public (remove-admin (admin principal))
  (begin
    (asserts! (is-admin) (err ERR-NOT-AUTHORIZED))
    (ok (map-delete admins admin))
  )
)

;; Add a new crop type
(define-public (add-crop-type
  (name (string-ascii 50))
  (description (string-ascii 200))
  (base-premium-rate uint)
  (max-coverage-per-acre uint)
)
  (let (
    (crop-id (var-get next-crop-id))
  )
    (asserts! (is-admin) (err ERR-NOT-AUTHORIZED))

    (var-set next-crop-id (+ crop-id u1))

    (ok (map-set crop-types
      { crop-id: crop-id }
      {
        name: name,
        description: description,
        base-premium-rate: base-premium-rate,
        max-coverage-per-acre: max-coverage-per-acre
      }
    ))
  )
)

;; Update a crop type
(define-public (update-crop-type
  (crop-id uint)
  (name (string-ascii 50))
  (description (string-ascii 200))
  (base-premium-rate uint)
  (max-coverage-per-acre uint)
)
  (begin
    (asserts! (is-admin) (err ERR-NOT-AUTHORIZED))
    (asserts! (is-some (map-get? crop-types { crop-id: crop-id })) (err ERR-CROP-NOT-FOUND))

    (ok (map-set crop-types
      { crop-id: crop-id }
      {
        name: name,
        description: description,
        base-premium-rate: base-premium-rate,
        max-coverage-per-acre: max-coverage-per-acre
      }
    ))
  )
)

;; Calculate premium for a policy
(define-read-only (calculate-premium
  (crop-id uint)
  (acres uint)
  (coverage-per-acre uint)
  (region-risk-factor uint)  ;; Risk factor from risk assessment contract (100 = neutral)
)
  (let (
    (crop (unwrap! (map-get? crop-types { crop-id: crop-id }) (err ERR-CROP-NOT-FOUND)))
    (base-premium-rate (get base-premium-rate crop))
    (max-coverage (get max-coverage-per-acre crop))
  )
    (asserts! (<= coverage-per-acre max-coverage) (err ERR-INVALID-PARAMETERS))
    (asserts! (> acres u0) (err ERR-INVALID-PARAMETERS))

    ;; Calculate premium: (base-rate * coverage * acres * risk-factor) / 100000
    ;; base-rate is per 1000 units of coverage, risk-factor is percentage (100 = 100%)
    (ok (/ (* (* (* base-premium-rate coverage-per-acre) acres) region-risk-factor) u100000))
  )
)

;; Issue a new policy
(define-public (issue-policy
  (policy-id (string-ascii 36))
  (crop-id uint)
  (acres uint)
  (coverage-per-acre uint)
  (start-date uint)
  (end-date uint)
  (region-id (string-ascii 10))
  (region-risk-factor uint)
)
  (let (
    (premium-amount (unwrap! (calculate-premium crop-id acres coverage-per-acre region-risk-factor) (err ERR-INVALID-PARAMETERS)))
    (farmer-count (default-to { count: u0 } (map-get? policy-count-by-farmer { farmer: tx-sender })))
  )
    (asserts! (is-none (map-get? policies { policy-id: policy-id })) (err ERR-POLICY-EXISTS))
    (asserts! (< start-date end-date) (err ERR-INVALID-PARAMETERS))
    (asserts! (>= start-date block-height) (err ERR-INVALID-PARAMETERS))

    ;; Update policy count for farmer
    (map-set policy-count-by-farmer
      { farmer: tx-sender }
      { count: (+ (get count farmer-count) u1) }
    )

    ;; Create the policy
    (ok (map-set policies
      { policy-id: policy-id }
      {
        farmer: tx-sender,
        crop-id: crop-id,
        acres: acres,
        coverage-per-acre: coverage-per-acre,
        premium-amount: premium-amount,
        start-date: start-date,
        end-date: end-date,
        status: "pending",
        region-id: region-id,
        premium-paid: false
      }
    ))
  )
)

;; Pay premium for a policy
(define-public (pay-premium (policy-id (string-ascii 36)))
  (let (
    (policy (unwrap! (map-get? policies { policy-id: policy-id }) (err ERR-POLICY-NOT-FOUND)))
  )
    (asserts! (is-eq (get farmer policy) tx-sender) (err ERR-NOT-AUTHORIZED))
    (asserts! (not (get premium-paid policy)) (err ERR-INVALID-PARAMETERS))

    ;; In a real implementation, this would involve a token transfer
    ;; For simplicity, we're just marking it as paid

    (ok (map-set policies
      { policy-id: policy-id }
      (merge policy {
        premium-paid: true,
        status: "active"
      })
    ))
  )
)

;; Mark a policy as claimed (called by claim processing contract)
(define-public (mark-policy-claimed (policy-id (string-ascii 36)))
  (let (
    (policy (unwrap! (map-get? policies { policy-id: policy-id }) (err ERR-POLICY-NOT-FOUND)))
  )
    (asserts! (is-admin) (err ERR-NOT-AUTHORIZED))
    (asserts! (is-eq (get status policy) "active") (err ERR-POLICY-NOT-ACTIVE))
    (asserts! (get premium-paid policy) (err ERR-PREMIUM-NOT-PAID))
    (asserts! (<= block-height (get end-date policy)) (err ERR-POLICY-EXPIRED))

    (ok (map-set policies
      { policy-id: policy-id }
      (merge policy { status: "claimed" })
    ))
  )
)

;; Get policy details
(define-read-only (get-policy (policy-id (string-ascii 36)))
  (map-get? policies { policy-id: policy-id })
)

;; Get crop type details
(define-read-only (get-crop-type (crop-id uint))
  (map-get? crop-types { crop-id: crop-id })
)

;; Get policies by farmer
(define-read-only (get-policy-count-by-farmer (farmer principal))
  (default-to { count: u0 } (map-get? policy-count-by-farmer { farmer: farmer }))
)

;; Check if a policy is active
(define-read-only (is-policy-active (policy-id (string-ascii 36)))
  (let (
    (policy (unwrap-panic (map-get? policies { policy-id: policy-id })))
  )
    (and
      (is-eq (get status policy) "active")
      (get premium-paid policy)
      (>= block-height (get start-date policy))
      (<= block-height (get end-date policy))
    )
  )
)
