# A brief list of pending things that need to be implemented

* Be more lenient towards failures during the attempt to update dependencies.yml in a module:
    * We could keep "failed" updates in the pending list, but we have to be careful about terminating the overall algorithm. Might be as simple as considering remaining pending changes as all failed if the todo list is empty otherwise.
