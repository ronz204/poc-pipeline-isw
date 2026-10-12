from pathlib import Path

import pytest

from source.extract import REQUIRED_COLUMNS, ExtractError, extract

HEADER = ",".join(REQUIRED_COLUMNS)
ROW = "1,Toy Car,Toys,7,10.09,2025-02-21,Colombia"
LIMIT = 1024 * 1024
DATA_DIR = Path(__file__).parents[1] / "data"


def write(tmp_path, content: str | bytes, name="in.csv") -> Path:
  path = tmp_path / name
  if isinstance(content, str):
    content = content.encode("utf-8")
  path.write_bytes(content)
  return path


def test_every_cell_is_read_as_text(tmp_path):
  path = write(tmp_path, f"{HEADER}\n0007,Toy Car,Toys,7,10.50,2025-02-21,Colombia\n")

  result = extract(path, LIMIT)

  assert list(result.rows.columns) == list(REQUIRED_COLUMNS)
  assert result.rows.iloc[0].tolist() == ["0007", "Toy Car", "Toys", "7", "10.50", "2025-02-21", "Colombia"]


def test_empty_fields_stay_empty_strings_and_na_words_stay_text(tmp_path):
  path = write(tmp_path, f"{HEADER}\n1,,Toys,NA,null,,None\n")

  row = extract(path, LIMIT).rows.iloc[0]

  assert row.tolist() == ["1", "", "Toys", "NA", "null", "", "None"]


def test_byte_order_mark_does_not_pollute_the_first_column(tmp_path):
  path = write(tmp_path, b"\xef\xbb\xbf" + f"{HEADER}\n{ROW}\n".encode())

  result = extract(path, LIMIT)

  assert result.rows.columns[0] == "transaction_id"
  assert result.rows.iloc[0]["transaction_id"] == "1"


def test_blank_line_stays_a_row_so_numbering_stays_aligned(tmp_path):
  path = write(tmp_path, f"{HEADER}\n{ROW}\n\n{ROW}\n")

  result = extract(path, LIMIT)

  assert result.rows.index.tolist() == [2, 3, 4]
  assert result.rows.loc[3].tolist() == [""] * len(REQUIRED_COLUMNS)
  assert result.rows_in == 3


def test_record_number_is_position_plus_two(tmp_path):
  path = write(tmp_path, f"{HEADER}\n{ROW}\n{ROW}\n{ROW}")

  assert extract(path, LIMIT).rows.index.tolist() == [2, 3, 4]


def test_header_without_data_rows_is_an_empty_result(tmp_path):
  result = extract(write(tmp_path, f"{HEADER}\n"), LIMIT)

  assert result.rows_in == 0
  assert list(result.rows.columns) == list(REQUIRED_COLUMNS)


def test_file_at_the_size_cap_is_read_and_one_byte_above_is_refused(tmp_path):
  content = f"{HEADER}\n{ROW}\n"
  path = write(tmp_path, content)
  size = len(content.encode())

  assert extract(path, size).rows_in == 1
  with pytest.raises(ExtractError, match="above the"):
    extract(path, size - 1)


def test_size_cap_is_checked_before_the_content_is_read(tmp_path):
  path = write(tmp_path, b"\xff\xfe not utf-8 at all")

  with pytest.raises(ExtractError, match="above the"):
    extract(path, 1)


@pytest.mark.parametrize("dropped", REQUIRED_COLUMNS)
def test_missing_required_column_names_it(tmp_path, dropped):
  kept = [name for name in REQUIRED_COLUMNS if name != dropped]
  path = write(tmp_path, ",".join(kept) + "\n" + ",".join("x" for _ in kept) + "\n")

  with pytest.raises(ExtractError, match=f"missing required columns: {dropped}"):
    extract(path, LIMIT)


def test_all_missing_columns_are_reported_together(tmp_path):
  path = write(tmp_path, "transaction_id,product\n1,a\n")

  with pytest.raises(ExtractError) as error:
    extract(path, LIMIT)

  assert "category, quantity, unit_price, transaction_date, country" in str(error.value)


def test_extra_columns_are_ignored_and_listed_by_name(tmp_path):
  path = write(tmp_path, f"notes,{HEADER},channel\nsecret,{ROW},web\n")

  result = extract(path, LIMIT)

  assert result.extra_columns == ("notes", "channel")
  assert list(result.rows.columns) == list(REQUIRED_COLUMNS)
  assert result.rows.iloc[0]["product"] == "Toy Car"


def test_columns_are_matched_by_name_not_by_position(tmp_path):
  reordered = ",".join(reversed(REQUIRED_COLUMNS))
  path = write(tmp_path, f"{reordered}\nColombia,2025-02-21,10.09,7,Toys,Toy Car,1\n")

  row = extract(path, LIMIT).rows.iloc[0]

  assert row.tolist() == ["1", "Toy Car", "Toys", "7", "10.09", "2025-02-21", "Colombia"]


def test_rows_with_the_wrong_column_count_are_kept_apart_with_their_values(tmp_path):
  path = write(tmp_path, f"{HEADER}\n{ROW}\n1,short\n{ROW},extra\n{ROW}\n")

  result = extract(path, LIMIT)

  assert result.rows.index.tolist() == [2, 5]
  assert [(m.record_number, m.values) for m in result.malformed] == [
    (3, ("1", "short")),
    (4, ("1", "Toy Car", "Toys", "7", "10.09", "2025-02-21", "Colombia", "extra")),
  ]
  assert result.rows_in == 4


def test_quoted_fields_keep_commas_and_quotes(tmp_path):
  path = write(tmp_path, f'{HEADER}\n1,"Mouse, wireless","Say ""hi""",7,10.09,2025-02-21,Colombia\n')

  row = extract(path, LIMIT).rows.iloc[0]

  assert row["product"] == "Mouse, wireless"
  assert row["category"] == 'Say "hi"'


def test_missing_file_is_an_extract_error(tmp_path):
  with pytest.raises(ExtractError, match="not found"):
    extract(tmp_path / "absent.csv", LIMIT)


def test_empty_file_is_an_extract_error(tmp_path):
  with pytest.raises(ExtractError, match="empty"):
    extract(write(tmp_path, ""), LIMIT)


def test_invalid_utf8_is_an_extract_error_that_does_not_echo_content(tmp_path):
  path = write(tmp_path, HEADER.encode() + b"\n1,caf\xe9,Toys,7,10.09,2025-02-21,Colombia\n")

  with pytest.raises(ExtractError, match="not valid UTF-8") as error:
    extract(path, LIMIT)

  assert "caf" not in str(error.value)


def test_clean_dataset_reads_all_rows():
  result = extract(DATA_DIR / "sales_valid.csv", LIMIT)

  assert result.rows_in == 1000
  assert result.malformed == ()
  assert result.extra_columns == ()


def test_defective_dataset_reads_all_rows_with_empty_product_kept_empty():
  result = extract(DATA_DIR / "sales_defective.csv", LIMIT)

  assert result.rows_in == 1000
  assert (result.rows["product"] == "").sum() == 2
