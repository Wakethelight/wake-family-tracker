CREATE TABLE IF NOT EXISTS user_status (
    id SERIAL PRIMARY KEY,
    user_id VARCHAR(50) NOT NULL,
    status VARCHAR(20) NOT NULL,
    team VARCHAR(50),
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Seed data (adapted from seed.py)
INSERT INTO user_status (user_id, status, team) VALUES
('alice', 'remote', 'team1'),
('bob', 'office', 'team2'),
('carol', 'leave', 'team1')
ON CONFLICT DO NOTHING;