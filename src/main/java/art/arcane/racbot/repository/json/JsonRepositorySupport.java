package art.arcane.racbot.repository.json;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.SerializationFeature;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;
import java.io.IOException;
import java.nio.channels.FileChannel;
import java.nio.channels.FileLock;
import java.nio.file.AtomicMoveNotSupportedException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.nio.file.StandardOpenOption;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public abstract class JsonRepositorySupport {
  protected final Logger logger = LoggerFactory.getLogger(getClass());
  protected final ObjectMapper mapper;
  private final Path dataRoot;
  private final boolean atomicWrites;

  protected JsonRepositorySupport(Path dataRoot, boolean atomicWrites) {
    this.dataRoot = dataRoot;
    this.atomicWrites = atomicWrites;
    this.mapper =
        new ObjectMapper()
            .registerModule(new JavaTimeModule())
            .disable(SerializationFeature.WRITE_DATES_AS_TIMESTAMPS)
            .enable(SerializationFeature.INDENT_OUTPUT);
  }

  protected Path dataRoot() {
    return dataRoot;
  }

  protected <T> Optional<T> read(Path path, Class<T> type) {
    if (!Files.exists(path)) {
      return Optional.empty();
    }

    try {
      withFileLock(lockFileFor(path), true);
      byte[] payload = Files.readAllBytes(path);
      if (payload.length == 0) {
        return Optional.empty();
      }
      return Optional.of(mapper.readValue(payload, type));
    } catch (Exception exception) {
      logger.warn("Corrupted JSON detected at {}. Moving to quarantine.", path, exception);
      quarantine(path);
      return Optional.empty();
    }
  }

  protected <T> T write(Path path, T value) {
    try {
      Files.createDirectories(path.getParent());
      Path lockFile = lockFileFor(path);
      withFileLock(lockFile, false);
      byte[] payload = mapper.writeValueAsBytes(value);
      if (atomicWrites) {
        writeAtomically(path, payload);
      } else {
        Files.write(
            path,
            payload,
            StandardOpenOption.CREATE,
            StandardOpenOption.TRUNCATE_EXISTING,
            StandardOpenOption.WRITE);
      }
      return value;
    } catch (IOException exception) {
      throw new IllegalStateException("Failed writing JSON file: " + path, exception);
    }
  }

  protected List<Path> listJsonFiles(Path directory) {
    if (!Files.isDirectory(directory)) {
      return List.of();
    }
    try {
      List<Path> files = new ArrayList<>();
      try (var stream = Files.list(directory)) {
        stream.filter(path -> path.getFileName().toString().endsWith(".json")).forEach(files::add);
      }
      return files;
    } catch (IOException exception) {
      logger.warn("Failed listing directory {}", directory, exception);
      return List.of();
    }
  }

  private void writeAtomically(Path path, byte[] payload) throws IOException {
    Path tempPath = path.resolveSibling(path.getFileName().toString() + ".tmp");
    Files.write(
        tempPath,
        payload,
        StandardOpenOption.CREATE,
        StandardOpenOption.TRUNCATE_EXISTING,
        StandardOpenOption.WRITE);
    try {
      Files.move(
          tempPath, path, StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE);
    } catch (AtomicMoveNotSupportedException ignored) {
      Files.move(tempPath, path, StandardCopyOption.REPLACE_EXISTING);
    }
  }

  private void withFileLock(Path lockPath, boolean shared) throws IOException {
    Files.createDirectories(lockPath.getParent());
    try (FileChannel lockChannel =
            FileChannel.open(
                lockPath,
                StandardOpenOption.CREATE,
                StandardOpenOption.READ,
                StandardOpenOption.WRITE);
        FileLock ignored = lockChannel.lock(0L, Long.MAX_VALUE, shared)) {
      // lock scope only
    }
  }

  private Path lockFileFor(Path path) {
    return path.resolveSibling(path.getFileName().toString() + ".lock");
  }

  private void quarantine(Path corruptedPath) {
    if (!Files.exists(corruptedPath)) {
      return;
    }
    Path quarantineDir = dataRoot.resolve("quarantine");
    String fileName =
        corruptedPath.getFileName().toString() + "." + Instant.now().toEpochMilli() + ".corrupt";
    Path destination = quarantineDir.resolve(fileName);
    try {
      Files.createDirectories(quarantineDir);
      Files.move(corruptedPath, destination, StandardCopyOption.REPLACE_EXISTING);
    } catch (IOException moveException) {
      logger.warn("Failed to quarantine corrupted file {}", corruptedPath, moveException);
    }
  }
}
