# Large Class

`Within · Bloaters · Measured Smells`

A class that has accumulated too many fields, methods, and reasons to exist, 
[Long Method](long-method.md) and
[Long Parameter List](long-parameter-list.md) raised to class scope. It grows
because, under time pressure, dropping new code into an existing class is
always cheaper than carving out a new one; eventually reading it takes a
morning, testing it means covering every combination of its state, and any
change risks breaking a responsibility you didn't know it had. The measured
size is the symptom; the disease is too many responsibilities in one place.

## Detection heuristics

### Agnostic

- Field and method counts far above the file's peers; the file scrolls for
  pages.
- Low cohesion: distinct clusters of methods each using a disjoint subset of
  the fields; the class is several classes sharing a namespace.
- A vague, role-free name: `Manager`, `Helper`, `Service`, `Utils`,
  `Processor`.
- Its test file is enormous, slow, or was quietly never written because setup
  requires half the system.
- Everything imports it, or it imports everything.

### PHP / Laravel

- God Eloquent models: a `User` or `Order` accreting query scopes, accessors,
  domain rules, formatting, and notification triggers, with a stack of
  traits (`HasThis`, `InteractsWithThat`) used to disguise the size rather
  than remove it.
- Fat controllers: many actions plus a tail of private helpers shared between
  them; each helper cluster is a service or action class in hiding.
- Catch-all `*Service` / `*Manager` classes that absorb every new feature in
  their domain because they're "where that kind of code goes".
- A constructor injecting a long list of dependencies, a
  [Long Parameter List](long-parameter-list.md) at class scale, signalling
  too many collaborators for one responsibility.

### TS / React

- God components: a pile of `useState`/`useRef` declarations serving several
  concerns at once (fetching, filtering, modals, form state) in one
  component body.
- Context providers bundling unrelated application state so every consumer
  re-renders for changes it doesn't care about.
- Ever-growing `utils.ts` / `api.ts` modules, or client classes with a method
  per endpoint plus caching plus retry plus serialization.
- Store/service classes mixing transport, caching, and domain rules behind
  one interface.

## Example

Authored for this card: upstream has no code example for this smell.

Smelly: one component owns the list, the filters, the selection, and the
export workflow:

```tsx
function OrdersPage() {
  const [orders, setOrders] = useState<Order[]>([]);
  const [loading, setLoading] = useState(false);
  const [status, setStatus] = useState<Status | 'all'>('all');
  const [query, setQuery] = useState('');
  const [sort, setSort] = useState<SortKey>('date');
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [exporting, setExporting] = useState(false);
  const [exportError, setExportError] = useState<string | null>(null);

  useEffect(() => { /* fetch + poll orders */ }, [status, query, sort]);

  const toggleRow = (id: string) => { /* selection bookkeeping */ };
  const exportSelected = async () => { /* build CSV, POST, download */ };

  return (
    <div>
      {/* ~200 lines of JSX: filter bar, sortable table, selection
          checkboxes, export dialog, error banners */}
    </div>
  );
}
```

Solution: each responsibility extracted into a hook or child component; the
page becomes composition:

```tsx
function OrdersPage() {
  const filters = useOrderFilters();
  const { orders, loading } = useOrders(filters);
  const selection = useRowSelection(orders);

  return (
    <div>
      <OrderFilterBar filters={filters} />
      <OrderTable orders={orders} loading={loading} selection={selection} />
      <ExportButton orders={selection.selected} />
    </div>
  );
}
```

## Refactorings

- Extract Class
- Extract Subclass
- Extract Interface
- Extract Domain Object
- Replace Data Value with Object

## Related smells

| Smell | Edge |
|---|---|
| [Dubious Abstraction](dubious-abstraction.md) | co-exist |
| [Long Method](long-method.md) | caused |
| [Long Parameter List](long-parameter-list.md) | caused |
| [Temporary Field](temporary-field.md) | caused |

Edge vocabulary: causes · caused (this smell is caused by it) · family ·
co-exist · antagonistic.

## Also known as

Blob, Brain Class, Complex Class, God Class, God Object, Schizophrenic Class,
Ice Berg Class

---

*Derivative work adapted from "Large Class" in Marcel Jerzyk's
[Code Smells Catalog](https://codesmells.org/) (MIT), see
[ATTRIBUTION.md](../ATTRIBUTION.md).*
