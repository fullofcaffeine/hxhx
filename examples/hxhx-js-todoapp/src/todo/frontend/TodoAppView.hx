package todo.frontend;

import coconut.data.ObservableArray;
import coconut.ui.View;
import todo.shared.TodoTypes.TodoFilter;
import todo.shared.TodoTypes.TodoItem;

class TodoAppView extends View {
	@:attribute final title:String;

	@:state var filter:TodoFilter = TodoFilter.All;
	@:state var items:ObservableArray<TodoItem> = [
		{
			id: 1,
			title: "Ship hxhx JS example",
			description: "Build the end-to-end todo demo.",
			done: false,
			createdAt: "2026-02-01T09:30:00Z",
		},
		{
			id: 2,
			title: "Document stage model",
			description: "Explain stage0/stage3 in beginner-friendly terms.",
			done: true,
			createdAt: "2026-02-02T09:30:00Z",
		},
		{
			id: 4,
			title: "Write release notes",
			description: "Summarize what shipped and what still needs stage polish.",
			done: false,
			createdAt: "2026-02-04T09:30:00Z",
		},
	];

	function render()
		'
    <main class="min-h-screen bg-background text-foreground">
      <div class="mx-auto max-w-5xl px-6 py-12 lg:px-10">
        <section class="relative overflow-hidden rounded-3xl border border-border/70 bg-card/80 p-8 shadow-2xl shadow-cyan-500/10 backdrop-blur">
          <div class="absolute -right-20 -top-24 h-72 w-72 rounded-full bg-cyan-400/20 blur-3xl" />
          <div class="absolute -bottom-16 -left-12 h-48 w-48 rounded-full bg-sky-300/20 blur-3xl" />
          <header class="relative z-10 flex flex-col gap-6 md:flex-row md:items-end md:justify-between">
            <div>
              <p class="text-xs font-semibold uppercase tracking-[0.25em] text-primary/90">HXHX Todoapp</p>
              <h1 class="mt-3 text-4xl font-extrabold tracking-tight text-card-foreground md:text-5xl">{title}</h1>
              <p class="mt-3 max-w-2xl text-sm text-muted-foreground md:text-base">A Coconut UI frontend with typed route metadata and SQL schema-driven output.</p>
            </div>
            <div class="grid grid-cols-3 gap-3 rounded-2xl border border-border/70 bg-background/80 p-3 text-center shadow-inner shadow-black/30">
              <MetricCard label="Total" value={items.length} />
              <MetricCard label="Open" value={openCount()} />
              <MetricCard label="Done" value={doneCount()} />
            </div>
          </header>
        </section>

        <section class="mt-8 rounded-3xl border border-border/70 bg-card/80 p-6 shadow-xl shadow-black/20">
          <div class="mb-6 flex flex-wrap gap-2">
            <FilterChip label="All" active={filter == TodoFilter.All} onclick={setFilter(TodoFilter.All)} />
            <FilterChip label="Open" active={filter == TodoFilter.Open} onclick={setFilter(TodoFilter.Open)} />
            <FilterChip label="Done" active={filter == TodoFilter.Done} onclick={setFilter(TodoFilter.Done)} />
          </div>

          <ul class="space-y-3">
            <for {item in filteredItems()}>
              <li class={rowClass(item.done)}>
                <div>
                  <h2 class="text-base font-semibold text-card-foreground">{item.title}</h2>
                  <p class="mt-1 text-sm text-muted-foreground">{item.description}</p>
                  <p class="mt-2 text-xs uppercase tracking-wide text-muted-foreground/80">Created {item.createdAt}</p>
                </div>
                <button class={buttonClass(item.done)} onclick={toggle(item.id)}>{item.done ? "Reopen" : "Done"}</button>
              </li>
            </for>
          </ul>
        </section>
      </div>
    </main>
  ';

	function filteredItems():Array<TodoItem>
		return switch filter {
			case TodoFilter.All: cloneItems(items.toArray());
			case TodoFilter.Open: [for (item in items) if (!item.done) cloneItem(item)];
			case TodoFilter.Done: [for (item in items) if (item.done) cloneItem(item)];
		}

	function toggle(id:Int):Void {
		items = [
			for (item in items)
				if (item.id == id) toggledItem(item) else cloneItem(item)
		];
	}

	function setFilter(next:TodoFilter):Void
		filter = next;

	function doneCount():Int {
		var count = 0;
		for (item in items) {
			if (item.done)
				count++;
		}
		return count;
	}

	function openCount():Int
		return items.length - doneCount();

	static function cloneItems(source:Array<TodoItem>):Array<TodoItem>
		return [for (item in source) cloneItem(item)];

	static function cloneItem(item:TodoItem):TodoItem {
		return {
			id: item.id,
			title: item.title,
			description: item.description,
			done: item.done,
			createdAt: item.createdAt,
		};
	}

	static function toggledItem(item:TodoItem):TodoItem {
		return {
			id: item.id,
			title: item.title,
			description: item.description,
			done: !item.done,
			createdAt: item.createdAt,
		};
	}

	static function rowClass(done:Bool):String {
		final stateTone = done ? "border-emerald-400/50 bg-emerald-500/10" : "border-border/70 bg-muted/30";
		return "flex items-center justify-between gap-4 rounded-2xl border p-4 transition-colors " + stateTone;
	}

	static function buttonClass(done:Bool):String {
		final stateTone = done ? "border-emerald-300/70 bg-emerald-400/20 text-emerald-100" : "border-primary/70 bg-primary/20 text-primary-foreground";
		return "rounded-xl border px-3 py-2 text-xs font-semibold uppercase tracking-wide transition hover:brightness-110 " + stateTone;
	}
}

class FilterChip extends View {
	@:attribute final label:String;
	@:attribute final active:Bool;
	@:attribute final onclick:Void->Void;

	function render()
		'
    <button class={chipClass(active)} onclick={onclick}>{label}</button>
  ';

	static function chipClass(active:Bool):String {
		final tone = active ? "border-primary/70 bg-primary/20 text-primary-foreground" : "border-input/70 bg-background/80 text-foreground";
		return "rounded-xl border px-3 py-2 text-xs font-semibold uppercase tracking-wide transition hover:brightness-110 " + tone;
	}
}

class MetricCard extends View {
	@:attribute final label:String;
	@:attribute final value:Int;

	function render()
		'
    <div class="rounded-xl border border-border/70 bg-card/80 px-3 py-2">
      <div class="text-xs uppercase tracking-wide text-muted-foreground">{label}</div>
      <div class="text-xl font-extrabold text-card-foreground">{value}</div>
    </div>
  ';
}
