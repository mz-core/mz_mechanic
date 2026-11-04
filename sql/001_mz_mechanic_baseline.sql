CREATE TABLE IF NOT EXISTS mz_mechanic_staff (
  citizenid VARCHAR(32) NOT NULL,
  workshop_code VARCHAR(48) NOT NULL,
  role VARCHAR(32) NOT NULL DEFAULT 'mechanic',
  active TINYINT(1) NOT NULL DEFAULT 1,
  granted_by VARCHAR(64) NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (citizenid, workshop_code),
  KEY idx_mz_mechanic_staff_workshop (workshop_code, active)
);

CREATE TABLE IF NOT EXISTS mz_mechanic_orders (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  public_id VARCHAR(40) NOT NULL,
  workshop_code VARCHAR(48) NOT NULL,
  bay_code VARCHAR(48) NOT NULL,
  vehicle_id BIGINT UNSIGNED NOT NULL,
  lock_vehicle_id BIGINT UNSIGNED NULL,
  vehicle_plate VARCHAR(16) NOT NULL,
  customer_citizenid VARCHAR(32) NOT NULL,
  assigned_mechanic_citizenid VARCHAR(32) NULL,
  state VARCHAR(32) NOT NULL,
  revision INT UNSIGNED NOT NULL DEFAULT 1,
  create_key VARCHAR(64) NOT NULL,
  last_operation_key VARCHAR(64) NULL,
  last_operation_fingerprint VARCHAR(255) NULL,
  diagnostic_json LONGTEXT NULL,
  quote_json LONGTEXT NULL,
  payment_json LONGTEXT NULL,
  application_json LONGTEXT NULL,
  failure_code VARCHAR(64) NULL,
  cancel_reason VARCHAR(120) NULL,
  expires_at TIMESTAMP NOT NULL,
  lock_expires_at TIMESTAMP NULL,
  completed_at TIMESTAMP NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_mz_mechanic_orders_public (public_id),
  UNIQUE KEY uq_mz_mechanic_orders_vehicle_lock (lock_vehicle_id),
  UNIQUE KEY uq_mz_mechanic_orders_create (customer_citizenid, create_key),
  KEY idx_mz_mechanic_orders_workshop_state (workshop_code, state),
  KEY idx_mz_mechanic_orders_customer (customer_citizenid, created_at),
  KEY idx_mz_mechanic_orders_mechanic (assigned_mechanic_citizenid, state)
);

CREATE TABLE IF NOT EXISTS mz_mechanic_order_events (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  order_id BIGINT UNSIGNED NOT NULL,
  event_type VARCHAR(64) NOT NULL,
  actor_id VARCHAR(64) NOT NULL,
  actor_role VARCHAR(24) NOT NULL,
  operation_key VARCHAR(64) NULL,
  payload_json LONGTEXT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_mz_mechanic_events_order (order_id, id),
  CONSTRAINT fk_mz_mechanic_events_order FOREIGN KEY (order_id) REFERENCES mz_mechanic_orders(id)
);

CREATE TABLE IF NOT EXISTS mz_mechanic_operations (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  order_id BIGINT UNSIGNED NOT NULL,
  operation_key VARCHAR(64) NOT NULL,
  request_fingerprint VARCHAR(255) NOT NULL,
  result_json LONGTEXT NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_mz_mechanic_operation (order_id, operation_key),
  CONSTRAINT fk_mz_mechanic_operations_order FOREIGN KEY (order_id) REFERENCES mz_mechanic_orders(id)
);
