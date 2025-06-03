// src/file_transfer/tests.rs
#[cfg(test)]
mod tests {
    use super::super::manager::FileTransferManager;
    use super::super::types::TransferConfig;
    use std::fs;
    use tempfile::tempdir;
    use tokio;

    #[tokio::test]
    async fn test_file_transfer_manager_creation() {
        let config = TransferConfig::default();
        let manager = FileTransferManager::new(config);
        assert!(manager.is_ok());
    }

    #[tokio::test]
    async fn test_prepare_single_file_transfer() {
        // Create a temporary file
        let temp_dir = tempdir().unwrap();
        let file_path = temp_dir.path().join("test.txt");
        fs::write(&file_path, "Hello, World!").unwrap();

        let config = TransferConfig::default();
        let manager = FileTransferManager::new(config).unwrap();

        let file_paths = vec![file_path];
        let result = manager.prepare_files_for_transfer(&file_paths).await;

        assert!(result.is_ok());
        let package = result.unwrap();
        assert_eq!(package.files.len(), 1);
        assert_eq!(package.files[0].name, "test.txt");
        assert!(package.total_size > 0);
    }

    #[tokio::test]
    async fn test_file_transfer_roundtrip() {
        // Create a temporary file
        let temp_dir = tempdir().unwrap();
        let source_file = temp_dir.path().join("source.txt");
        let test_content = "This is test content for file transfer!";
        fs::write(&source_file, test_content).unwrap();

        let config = TransferConfig::default();
        let mut manager = FileTransferManager::new(config).unwrap();

        // Prepare file for transfer
        let file_paths = vec![source_file];
        let package = manager
            .prepare_files_for_transfer(&file_paths)
            .await
            .unwrap();

        // Receive the files
        let received_paths = manager.receive_files(package).await.unwrap();

        assert_eq!(received_paths.len(), 1);

        // Verify the content
        let received_content = fs::read_to_string(&received_paths[0]).unwrap();
        assert_eq!(received_content, test_content);
    }

    #[tokio::test]
    async fn test_large_file_chunking() {
        let temp_dir = tempdir().unwrap();
        let large_file = temp_dir.path().join("large.txt");

        // Create a file larger than default chunk size (1MB)
        let large_content = "A".repeat(2 * 1024 * 1024); // 2MB of 'A's
        fs::write(&large_file, &large_content).unwrap();

        let config = TransferConfig::default();
        let mut manager = FileTransferManager::new(config).unwrap();

        // Prepare file for transfer
        let file_paths = vec![large_file];
        let package = manager
            .prepare_files_for_transfer(&file_paths)
            .await
            .unwrap();

        // Should have multiple chunks
        assert!(package.files[0].chunks.len() > 1);

        // Test receive
        let received_paths = manager.receive_files(package).await.unwrap();
        let received_content = fs::read_to_string(&received_paths[0]).unwrap();
        assert_eq!(received_content, large_content);
    }
}
