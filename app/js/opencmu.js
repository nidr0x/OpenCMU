(function () {
  'use strict';

  var STATE_URL = 'state.json';

  function byId(id) {
    return document.getElementById(id);
  }

  function setText(id, value) {
    var node = byId(id);
    if (node) {
      node.textContent = value;
    }
  }

  function formatTime(value) {
    if (!value) {
      return '—';
    }
    var date = new Date(value);
    if (isNaN(date.getTime())) {
      return String(value);
    }
    return date.toLocaleString();
  }

  function renderTweaks(tweaks) {
    var list = byId('tweaks');
    if (!list) {
      return;
    }

    while (list.firstChild) {
      list.removeChild(list.firstChild);
    }

    if (!tweaks || !tweaks.length) {
      var empty = document.createElement('li');
      empty.className = 'muted';
      empty.textContent = 'No tweaks recorded.';
      list.appendChild(empty);
      return;
    }

    for (var i = 0; i < tweaks.length; i++) {
      var item = document.createElement('li');

      var id = document.createElement('span');
      id.className = 'id';
      id.textContent = String(tweaks[i]);

      var name = document.createElement('span');
      name.className = 'name';
      name.textContent = 'applied';

      item.appendChild(id);
      item.appendChild(name);
      list.appendChild(item);
    }
  }

  function render(state) {
    setText('project', state.project || 'OpenCMU');
    setText('version', state.version ? 'v' + state.version : '—');
    setText('firmware', state.firmware || 'unknown');
    setText('installed', state.installed_at ? 'recorded' : 'not installed');
    setText('installed-time', formatTime(state.installed_at));
    setText('backup', state.backup_dir || 'No backup recorded.');
    renderTweaks(state.tweaks);
  }

  function fail(message) {
    var list = byId('tweaks');
    if (list) {
      while (list.firstChild) {
        list.removeChild(list.firstChild);
      }
      var item = document.createElement('li');
      item.className = 'muted';
      item.textContent = message;
      list.appendChild(item);
    }
    setText('installed', 'unknown');
  }

  function load() {
    var xhr = new XMLHttpRequest();
    xhr.open('GET', STATE_URL + '?t=' + new Date().getTime(), true);

    xhr.onreadystatechange = function () {
      if (xhr.readyState !== 4) {
        return;
      }

      if (xhr.status >= 200 && xhr.status < 300) {
        try {
          render(JSON.parse(xhr.responseText));
        } catch (err) {
          fail('state.json is not valid JSON.');
        }
        return;
      }

      fail('No state.json next to this dashboard.');
    };

    xhr.send(null);
  }

  var refresh = byId('refresh');
  if (refresh) {
    refresh.onclick = load;
  }

  load();
})();
