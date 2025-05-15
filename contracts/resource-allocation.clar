;; Resource Allocation Contract
;; Manages deployment of city services

(define-data-var last-resource-id uint u0)
(define-data-var last-allocation-id uint u0)

;; Resource types: 1=Vehicle, 2=Equipment, 3=Personnel, 4=Funds, 5=Materials
(define-map resources
  { resource-id: uint }
  {
    resource-type: uint,
    name: (string-utf8 100),
    capacity: uint,
    status: uint, ;; 1=Available, 2=In Use, 3=Maintenance, 4=Decommissioned
    owner: principal
  }
)

(define-map resource-allocations
  { allocation-id: uint }
  {
    resource-id: uint,
    task-id: (optional uint),
    asset-id: (optional uint),
    start-time: uint,
    end-time: uint,
    status: uint, ;; 1=Scheduled, 2=In Progress, 3=Completed, 4=Cancelled
    allocated-by: principal
  }
)

(define-read-only (get-resource (resource-id uint))
  (map-get? resources { resource-id: resource-id })
)

(define-read-only (get-allocation (allocation-id uint))
  (map-get? resource-allocations { allocation-id: allocation-id })
)

(define-read-only (get-last-resource-id)
  (var-get last-resource-id)
)

(define-read-only (get-last-allocation-id)
  (var-get last-allocation-id)
)

(define-public (register-resource
    (resource-type uint)
    (name (string-utf8 100))
    (capacity uint))
  (let
    (
      (new-resource-id (+ (var-get last-resource-id) u1))
    )
    (asserts! (and (>= resource-type u1) (<= resource-type u5)) (err u1)) ;; Valid resource type
    (var-set last-resource-id new-resource-id)
    (map-set resources
      { resource-id: new-resource-id }
      {
        resource-type: resource-type,
        name: name,
        capacity: capacity,
        status: u1, ;; Available by default
        owner: tx-sender
      }
    )
    (ok new-resource-id)
  )
)

(define-public (update-resource-status (resource-id uint) (new-status uint))
  (let
    (
      (resource (unwrap! (get-resource resource-id) (err u404)))
    )
    (asserts! (is-eq tx-sender (get owner resource)) (err u403))
    (asserts! (and (>= new-status u1) (<= new-status u4)) (err u1))
    (map-set resources
      { resource-id: resource-id }
      (merge resource { status: new-status })
    )
    (ok true)
  )
)

(define-public (allocate-resource
    (resource-id uint)
    (task-id (optional uint))
    (asset-id (optional uint))
    (start-time uint)
    (end-time uint))
  (let
    (
      (resource (unwrap! (get-resource resource-id) (err u404)))
      (new-allocation-id (+ (var-get last-allocation-id) u1))
    )
    ;; Check if resource is available
    (asserts! (is-eq (get status resource) u1) (err u2))
    ;; Check if start time is before end time
    (asserts! (< start-time end-time) (err u3))

    (var-set last-allocation-id new-allocation-id)

    ;; Create allocation
    (map-set resource-allocations
      { allocation-id: new-allocation-id }
      {
        resource-id: resource-id,
        task-id: task-id,
        asset-id: asset-id,
        start-time: start-time,
        end-time: end-time,
        status: u1, ;; Scheduled by default
        allocated-by: tx-sender
      }
    )

    ;; Update resource status to In Use
    (map-set resources
      { resource-id: resource-id }
      (merge resource { status: u2 })
    )

    (ok new-allocation-id)
  )
)

(define-public (update-allocation-status (allocation-id uint) (new-status uint))
  (let
    (
      (allocation (unwrap! (get-allocation allocation-id) (err u404)))
      (resource-id (get resource-id allocation))
      (resource (unwrap! (get-resource resource-id) (err u404)))
    )
    (asserts! (is-eq tx-sender (get allocated-by allocation)) (err u403))
    (asserts! (and (>= new-status u1) (<= new-status u4)) (err u1))

    ;; Update allocation status
    (map-set resource-allocations
      { allocation-id: allocation-id }
      (merge allocation { status: new-status })
    )

    ;; If completed or cancelled, set resource back to available
    (if (or (is-eq new-status u3) (is-eq new-status u4))
      (map-set resources
        { resource-id: resource-id }
        (merge resource { status: u1 })
      )
      true
    )

    (ok true)
  )
)
