-- An in-memory stand-in for src/adapter's PersistentDB store that counts writes. fakeStore(data) starts from
-- data, { [key] = saved table }, and exposes it as store.data.
return function(data)
  local store = { data = data or {}, writes = 0 }
  function store.get(key)
    return store.data[key]
  end
  function store.set(key, value)
    store.writes = store.writes + 1
    store.data[key] = value
  end
  return store
end
