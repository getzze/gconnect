void main (string[] args) {
    Test.init (ref args);

    TestSuite.get_root ().add_suite (new MyClassTest ().get_suite ());

    Test.run ();
}