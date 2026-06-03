
-- Extension VectorDB
CREATE EXTENSION IF NOT EXISTS vector;

-- Schema
CREATE SCHEMA IF NOT EXISTS auth;
CREATE SCHEMA IF NOT EXISTS rag_core;

-- === Schema AUTH === 
-- Khởi tạo kiểu ENUM cho Role
CREATE TYPE auth.user_role_enum AS ENUM ('admin', 'user');

-- BẢNG 1: ACCOUNTS (Lưu thông tin cốt lõi để đăng nhập)
CREATE TABLE auth.accounts (
    account_id SERIAL PRIMARY KEY,
    email VARCHAR(255) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    role auth.user_role_enum DEFAULT 'user',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP NULL,
    is_delete BOOLEAN DEFAULT FALSE,
    deleted_by INT REFERENCES auth.accounts(account_id) 
);

-- BẢNG 2: ADMIN PROFILES (Hồ sơ dành riêng cho Admin)
CREATE TABLE auth.admin_profiles (
    admin_id SERIAL PRIMARY KEY,
    full_name VARCHAR(50) NOT NULL,
    admin_level VARCHAR(20) DEFAULT 'moderator',
    last_login_at TIMESTAMP NULL, 
    account_id INT NOT NULL UNIQUE REFERENCES auth.accounts(account_id) ON DELETE CASCADE
);

-- BẢNG 3: USER PROFILES (Hồ sơ và Quản lý tài nguyên của User)
CREATE TABLE auth.user_profiles (
    user_id SERIAL PRIMARY KEY,
    full_name VARCHAR(50) NOT NULL,
    storage_quota BIGINT DEFAULT 104857600, -- 100MB
    used_storage BIGINT DEFAULT 0,
    api_call_count INT DEFAULT 0, 
    account_id INT NOT NULL UNIQUE REFERENCES auth.accounts(account_id) ON DELETE CASCADE
);


-- === Schema RAG_CORE (LÕI NGHIỆP VỤ HỆ THỐNG AI) ===

-- BẢNG QUẢN LÝ MÔN HỌC
CREATE TABLE rag_core.subjects (    
    subj_id SERIAL PRIMARY KEY,
    subj_name VARCHAR(255) NOT NULL,
    subj_code VARCHAR(50),
    subj_created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    subj_deleted_at TIMESTAMP NULL,
    is_delete BOOLEAN DEFAULT FALSE,
    subj_account_id INT REFERENCES auth.accounts(account_id), -- Đổi thành account_id
    subj_deleted_by INT REFERENCES auth.accounts(account_id)
);

-- BẢNG LƯU THÔNG TIN FILE
CREATE TABLE rag_core.documents (
    doc_id SERIAL PRIMARY KEY,
    doc_original_name VARCHAR(255) NOT NULL,
    doc_storage_url VARCHAR(500) NOT NULL,
    doc_file_size BIGINT NOT NULL,
    doc_status VARCHAR(20) DEFAULT 'pending',   
    doc_uploaded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    doc_deleted_at TIMESTAMP NULL,
    is_delete BOOLEAN DEFAULT FALSE, 
    doc_account_id INT REFERENCES auth.accounts(account_id), 
    doc_subject_id INT REFERENCES rag_core.subjects(subj_id),
    doc_deleted_by INT REFERENCES auth.accounts(account_id)
);

-- BẢNG CHỨA DỮ LIỆU VECTOR
CREATE TABLE rag_core.document_chunks (
    chunk_id BIGSERIAL PRIMARY KEY, 
    chunk_index INT NOT NULL,
    chunk_content TEXT NOT NULL,
    chunk_embedding VECTOR(384), 
    chunk_document_id INT REFERENCES rag_core.documents(doc_id) ON DELETE CASCADE
);

-- BẢNG QUẢN LÝ PHIÊN CHAT
CREATE TABLE rag_core.chat_sessions (
    session_id SERIAL PRIMARY KEY,
    session_title VARCHAR(255),
    session_created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    session_deleted_at TIMESTAMP NULL,
    is_delete BOOLEAN DEFAULT FALSE,
    session_account_id INT REFERENCES auth.accounts(account_id), 
    session_deleted_by INT REFERENCES auth.accounts(account_id)
);

-- BẢNG CHI TIẾT TIN NHẮN
CREATE TABLE rag_core.chat_messages (
    mess_id BIGSERIAL PRIMARY KEY,
    mess_role VARCHAR(10) NOT NULL CHECK (mess_role IN ('user','ai')),
    mess_content TEXT NOT NULL,
    mess_tokens INT NULL,
    mess_created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    mess_session_id INT REFERENCES rag_core.chat_sessions(session_id) ON DELETE CASCADE
);

-- BẢNG CHIA SẺ TÀI LIỆU
CREATE TABLE rag_core.document_shares (
    share_id SERIAL PRIMARY KEY,
    share_token VARCHAR(64) NOT NULL UNIQUE,
    expires_at TIMESTAMP NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, 
    shared_account_id INT NOT NULL REFERENCES auth.accounts(account_id), 
    created_by INT NOT NULL REFERENCES auth.accounts(account_id),
    doc_id INT NOT NULL REFERENCES rag_core.documents(doc_id) ON DELETE CASCADE
);


-- TRIGGERS XỬ LÝ CASCADE KHI SOFT DELETE
-- Trigger 1: Soft Delete Document -> Hard Delete Document_Chunks
CREATE OR REPLACE FUNCTION rag_core.trg_cascade_soft_delete_document()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.is_delete = TRUE AND OLD.is_delete = FALSE THEN
        DELETE FROM rag_core.document_chunks WHERE chunk_document_id = NEW.doc_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_soft_delete_doc
AFTER UPDATE OF is_delete ON rag_core.documents
FOR EACH ROW
EXECUTE FUNCTION rag_core.trg_cascade_soft_delete_document();


-- Trigger 2: Soft Delete Chat_Session -> Hard Delete Chat_Messages
CREATE OR REPLACE FUNCTION rag_core.trg_cascade_soft_delete_session()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.is_delete = TRUE AND OLD.is_delete = FALSE THEN
        DELETE FROM rag_core.chat_messages WHERE mess_session_id = NEW.session_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_soft_delete_session
AFTER UPDATE OF is_delete ON rag_core.chat_sessions
FOR EACH ROW
EXECUTE FUNCTION rag_core.trg_cascade_soft_delete_session();