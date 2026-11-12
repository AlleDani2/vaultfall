extends GutTest
## NumberFormat.cell (F16, docs/ui_redesign/02 §5.3): quantità nella cella della griglia del Deposito.


func test_fino_a_9999_intero_con_le_migliaia_della_lingua() -> void:
	assert_eq(NumberFormat.cell(1.0, "it"), "1")
	assert_eq(NumberFormat.cell(840.0, "it"), "840")
	assert_eq(NumberFormat.cell(9999.0, "it"), "9.999")
	assert_eq(NumberFormat.cell(9999.0, "en"), "9,999")


func test_bordo_9999_10000() -> void:
	assert_eq(NumberFormat.cell(10000.0, "it"), "10 K")
	assert_eq(NumberFormat.cell(10000.0, "en"), "10K")
	assert_eq(NumberFormat.cell(12345.0, "it"), "12,3 K")
	assert_eq(NumberFormat.cell(12345.0, "en"), "12.3K")
	assert_eq(NumberFormat.cell(12000.0, "it"), "12 K", "niente decimale inutile")


func test_bordo_999999_1000000() -> void:
	assert_eq(NumberFormat.cell(123456.0, "it"), "123 K")
	assert_eq(NumberFormat.cell(999499.0, "it"), "999 K")
	assert_eq(NumberFormat.cell(999999.0, "it"), "1 M", "999.999 arrotonda al milione, mai «1000 K»")
	assert_eq(NumberFormat.cell(999999.0, "en"), "1M")
	assert_eq(NumberFormat.cell(1000000.0, "it"), "1 M")


func test_milioni_e_oltre() -> void:
	assert_eq(NumberFormat.cell(1250000.0, "it"), "1,25 M")
	assert_eq(NumberFormat.cell(1250000.0, "en"), "1.25M")
	assert_eq(NumberFormat.cell(12500000.0, "it"), "12,5 M")
	assert_eq(NumberFormat.cell(2.5e9, "en"), "2.5B")


func test_ogni_valore_sta_in_pochi_caratteri() -> void:
	for n in [1.0, 99.0, 1234.0, 9999.0, 10000.0, 99999.0, 100000.0, 999999.0, 1e6, 5.55e7, 1e9, 1e12, 1e30]:
		assert_lte(NumberFormat.cell(n, "it").length(), 8, "«%s» entra nella cella" % NumberFormat.cell(n, "it"))
