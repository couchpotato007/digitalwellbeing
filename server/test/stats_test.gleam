import categories.{Rule}
import stats

pub fn merge_test() {
  assert stats.merge([#(0, 10), #(5, 20), #(30, 40)], 0)
    == [#(0, 20), #(30, 40)]
  assert stats.merge([#(0, 10), #(15, 20), #(30, 40)], 5)
    == [#(0, 20), #(30, 40)]
  assert stats.union_ms([#(0, 10), #(5, 20), #(30, 40)]) == 30
}

pub fn color_slot_test() {
  let order =
    stats.category_order([
      Rule(0, "Work > Programming", "", True, []),
      Rule(0, "Media > Video", "", True, []),
      Rule(0, "Work > Office", "", True, []),
    ])
  assert order == ["Work", "Media"]
  assert stats.color_slot(order, "Work > Office") == Ok(0)
  assert stats.color_slot(order, "Media") == Ok(1)
  assert stats.color_slot(order, "Uncategorized") == Error(Nil)
}

pub fn change_test() {
  assert stats.change(150, 100) == Ok(50)
  assert stats.change(50, 100) == Ok(-50)
  assert stats.change(50, 0) == Error(Nil)
}
