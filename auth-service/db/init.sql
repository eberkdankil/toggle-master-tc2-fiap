CREATE TABLE IF NOT EXISTS api_keys (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    
    -- key_hash armazena o hash SHA-256 da chave, que tem 64 caracteres hexadecimais
    key_hash VARCHAR(64) NOT NULL UNIQUE, 
    
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Chave de serviço fixa (usada pelo evaluation-service, SERVICE_API_KEY).
-- Chave em texto plano: tm_key_e5873e855f9948ea109faecc22ca0f4f0dd0885e80c51e8f5d46e1b14e645bfb
-- Hash abaixo = SHA-256 dessa chave (conferido, bate certinho).
INSERT INTO api_keys (name, key_hash)
VALUES ('service-key', 'd0773936455d431211e4419452837ca14acd6f67898dd9075e27abf54d8a8584')
ON CONFLICT (key_hash) DO NOTHING;