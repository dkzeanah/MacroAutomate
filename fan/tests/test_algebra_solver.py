import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("algebra_solver", Path(__file__).with_name("algebra_solver.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class AlgebraTests(unittest.TestCase):
    def test_numeric_rational_power(self):
        r = module.solve({"mode": "simplify", "expression": "100^(1/2)"})
        self.assertEqual(r["value"], "10")
        self.assertFalse(r["not_real"])

    def test_exact_radical_value(self):
        self.assertEqual(module.solve({"mode": "simplify", "expression": "2^(1/2)"})["value"], "sqrt(2)")

    def test_non_real_radical_choice(self):
        self.assertTrue(module.solve({"mode": "simplify", "expression": "(-4)^(1/2)"})["not_real"])

    def test_real_odd_root(self):
        self.assertEqual(module.solve({"mode": "simplify", "expression": "(-8)^(1/3)"})["value"], "-2")

    def test_numeric_expression_rejects_variables(self):
        with self.assertRaises(ValueError):
            module.solve({"mode": "simplify", "expression": "x^(1/2)"})

    def result(self, equations, variables=("x",), proposed=None):
        return module.solve({"equations": equations, "variables": list(variables), "proposed_solutions": proposed or []})

    def test_fraction_linear(self):
        r = self.result(["(3*x-2)/4-(x+1)/3=25/12"], proposed=[{"x":"7"}])
        self.assertEqual(r["solutions"], [{"x":"7"}])
        self.assertTrue(r["proposed_matched"])

    def test_quadratic_all_roots(self):
        self.assertEqual(self.result(["x^2-5*x+6=0"])["solutions"], [{"x":"2"}, {"x":"3"}])

    def test_system(self):
        self.assertEqual(self.result(["2*x+y=11", "x-y=1"], ("x","y"))["solutions"], [{"x":"4","y":"3"}])

    def test_radical_no_extraneous_root(self):
        self.assertEqual(self.result(["sqrt(x+5)=x-1"])["solutions"], [{"x":"4"}])

    def test_rational_domain_hole(self):
        self.assertEqual(self.result(["(x^2-1)/(x-1)=3"])["solutions"], [{"x":"2"}])

    def test_exact_decimals(self):
        self.assertEqual(self.result(["0.1*x=0.3"])["solutions"], [{"x":"3"}])

    def test_implicit_coefficients(self):
        self.assertEqual(self.result(["x²-5x+6=0"])["solutions"], [{"x":"2"}, {"x":"3"}])

    def test_implicit_parentheses(self):
        self.assertEqual(self.result(["3(x-1)=9"])["solutions"], [{"x":"4"}])

    def test_implicit_variable_product(self):
        self.assertEqual(self.result(["xy=6", "y=2"], ("x","y"))["solutions"], [{"x":"3","y":"2"}])

    def test_ambiguous_variable_suffix_rejected(self):
        with self.assertRaises(ValueError): self.result(["x2=4"])

    def test_irrational_root(self):
        self.assertEqual(len(self.result(["x^2=2"])["solutions"]), 2)

    def test_wrong_model_solution_detected(self):
        self.assertFalse(self.result(["x+1=4"], proposed=[{"x":"4"}])["proposed_matched"])

    def test_partial_model_roots_detected(self):
        self.assertFalse(self.result(["x^2=4"], proposed=[{"x":"2"}])["proposed_matched"])

    def test_model_root_order_irrelevant(self):
        self.assertTrue(self.result(["x^2=4"], proposed=[{"x":"2"},{"x":"-2"}])["proposed_matched"])

    def test_parameterized_rejected(self):
        with self.assertRaises(ValueError): self.result(["x+y=1"], ("x","y"))

    def test_infinite_rejected(self):
        with self.assertRaises(ValueError): self.result(["x=x"])

    def test_no_real_solution_rejected(self):
        with self.assertRaises(ValueError): self.result(["x^2=-1"])

    def test_import_and_call_rejected(self):
        with self.assertRaises(ValueError): self.result(["__import__('os').system('echo injection')=0"])

    def test_attribute_rejected(self):
        with self.assertRaises(ValueError): self.result(["x.__class__=1"])

    def test_comprehension_rejected(self):
        with self.assertRaises(ValueError): self.result(["[x for x in [1]]=1"])

    def test_unknown_name_rejected(self):
        with self.assertRaises(ValueError): self.result(["a=3"])

    def test_excessive_power_rejected(self):
        with self.assertRaises(ValueError): self.result(["x^999999=3"])

    def test_variable_exponent_rejected(self):
        with self.assertRaises(ValueError): self.result(["2^x=4"])

    def test_extra_equals_rejected(self):
        with self.assertRaises(ValueError): self.result(["x=3=4"])

    def test_zero_denominator_rejected(self):
        with self.assertRaises(ValueError): self.result(["x/0=3"])

    def test_duplicate_variable_rejected(self):
        with self.assertRaises(ValueError): self.result(["x=3"], ("x","x"))

    def test_wrong_solution_keys_rejected(self):
        with self.assertRaises(ValueError): self.result(["x=3"], proposed=[{"y":"3"}])


if __name__ == "__main__":
    unittest.main(verbosity=2)
