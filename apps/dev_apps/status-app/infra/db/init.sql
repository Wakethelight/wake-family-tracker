CREATE TABLE IF NOT EXISTS user_status (
    id SERIAL PRIMARY KEY,
    user_id VARCHAR(50) NOT NULL,
    status VARCHAR(20) NOT NULL,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Seed data (adapted from seed.py)
INSERT INTO user_status (user_id, status) VALUES
('alice', 'remote'),
('bob', 'office'),
('carol', 'home')
ON CONFLICT DO NOTHING;