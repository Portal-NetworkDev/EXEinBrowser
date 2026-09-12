const input = document.getElementById('file');
const drop = document.getElementById('drop');
const name = document.getElementById('file-name');
const run = document.getElementById('run');
const status = document.getElementById('status');
let selected = null;

function selectFile(file) {
  if (!file) {
    return;
  }

  const lower = file.name.toLowerCase();

  if (!lower.endsWith('.exe')) {
    status.textContent = 'Please choose a Windows .exe file.';
    run.disabled = true;
    selected = null;
    return;
  }

  selected = file;
  name.textContent = file.name;
  status.textContent = `${(file.size / 1024 / 1024).toFixed(2)} MB selected`;
  run.disabled = false;
}

input.addEventListener('change', () => {
  selectFile(input.files[0]);
});

['dragenter', 'dragover'].forEach(type => {
  drop.addEventListener(type, event => {
    event.preventDefault();
    drop.classList.add('dragging');
  });
});

['dragleave', 'drop'].forEach(type => {
  drop.addEventListener(type, event => {
    event.preventDefault();
    drop.classList.remove('dragging');
  });
});

drop.addEventListener('drop', event => {
  selectFile(event.dataTransfer.files[0]);
});

function openDatabase() {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open('webexe', 1);

    request.onupgradeneeded = () => {
      request.result.createObjectStore('files');
    };

    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}

async function storeFile(file) {
  const database = await openDatabase();

  await new Promise((resolve, reject) => {
    const transaction = database.transaction('files', 'readwrite');
    const store = transaction.objectStore('files');

    store.put({
      blob: file,
      name: file.name,
      type: file.type
    }, 'selected');

    transaction.oncomplete = resolve;
    transaction.onerror = () => reject(transaction.error);
  });

  database.close();
}

run.addEventListener('click', async () => {
  if (!selected) {
    return;
  }

  run.disabled = true;
  status.textContent = 'Preparing the Windows program...';

  try {
    await storeFile(selected);
    location.href = `runner.html?auto=false&p=d:/${encodeURIComponent(selected.name)}`;
  } catch (error) {
    status.textContent = `Could not prepare the file: ${error.message}`;
    run.disabled = false;
  }
});
