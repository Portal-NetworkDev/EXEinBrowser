// the runner grew legs. i mean... what???

function openDatabase() {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open('webexe', 1);

    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}

async function getStoredFile() {
  const database = await openDatabase();

  const record = await new Promise((resolve, reject) => {
    const transaction = database.transaction('files', 'readonly');
    const request = transaction.objectStore('files').get('selected');

    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });

  database.close();
  return record;
}

async function clearStoredFile() {
  const database = await openDatabase();

  await new Promise((resolve, reject) => {
    const transaction = database.transaction('files', 'readwrite');
    transaction.objectStore('files').delete('selected');
    transaction.oncomplete = resolve;
    transaction.onerror = () => reject(transaction.error);
  });

  database.close();
}

function runnerReady() {
  const startButton = document.getElementById('startbtn');
  return typeof start === 'function' && startButton && startButton.style.display !== 'none' && !startButton.disabled;
}

function fileExists(path) {
  try {
    FS.lookupPath(path, { follow: true });
    return true;
  } catch (error) {
    return false;
  }
}

async function loadStoredFile() {
  try {
    const record = await getStoredFile();

    if (!record || !record.blob) {
      throw new Error('No EXE was found. Return to WebEXE and choose a file again.');
    }

    const file = new File([record.blob], record.name, {
      type: record.type || 'application/x-msdownload'
    });
    const targetPath = `/d_drive/${record.name}`;
    const statusElement = document.getElementById('status');
    const waitForRunner = setInterval(() => {
      if (!runnerReady()) {
        return;
      }

      clearInterval(waitForRunner);
      statusElement.textContent = `Loading ${record.name}...`;

      try {
        if (fileExists(targetPath)) {
          FS.unlink(targetPath);
        }
        uploadFile(file);
      } catch (error) {
        statusElement.textContent = `Could not load ${record.name}: ${error.message}`;
        return;
      }

      const waitForFile = setInterval(async () => {
        if (!fileExists(targetPath)) {
          return;
        }

        clearInterval(waitForFile);
        statusElement.textContent = `Starting ${record.name}...`;
        await clearStoredFile();
        start();
      }, 100);
    }, 100);
  } catch (error) {
    document.getElementById('status').textContent = error.message;
  }
}

loadStoredFile();
