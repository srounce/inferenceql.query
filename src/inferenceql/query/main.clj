(ns inferenceql.query.main
  (:refer-clojure :exclude [eval print])
  (:import [tech.tablesaw.api Row]
           [tech.tablesaw.api Table])
  (:require [clojure.core :as clojure]
            [clojure.data.csv :as csv]
            [clojure.main :as main]
            [clojure.pprint :as pprint]
            [clojure.repl :as repl]
            [clojure.string :as string]
            [clojure.tools.cli :as cli]
            [inferenceql.inference.gpm :as gpm]
            [inferenceql.query :as query]
            [medley.core :as medley]))

(def output-formats #{"csv" "table"})

(defn parse-named-pair
  [s]
  (when-let [[_ name path] (re-matches #"([^=]+)=([^=]+)" s)]
    {name path}))

(def cli-options
  [["-t" "--table NAME=PATH" "table CSV name and path"
    :multi true
    :default []
    :update-fn conj
    :validate [parse-named-pair "Must be of the form: NAME=PATH"]]
   ["-m" "--model NAME=PATH" "model EDN name and path"
    :multi true
    :default []
    :update-fn conj
    :validate [parse-named-pair "Must be of the form: NAME=PATH"]]
   ["-e" "--eval STRING" "evaluate query in STRING"]
   ["-o" "--output FORMAT" "output format"
    :validate [output-formats (str "Must be one of: " (string/join ", " output-formats))]]
   ["-h" "--help"]])

(defn slurp-model
  "Opens a reader on x, reads its contents, parses its contents into EDN
  specification, and from that specification creates a multimixture model. See
  `clojure.java.io/reader` for a complete list of supported arguments."
  [x]
  (-> (slurp x) (gpm/read-string)))

(defn model
  "Attempts to coerce `x` into a model. `x` must either return a multimixture
  specification when read with `clojure.java.io/reader` or be a valid
  `inferenceql.inference.gpm/http` server. "
  [x]
  (try (slurp-model x)
       (catch java.io.FileNotFoundException e
         (if (re-find #"https?://" x)
           (gpm/http x)
           (throw e)))))

(defn slurp-csv
  "Opens a reader on x, reads its contents, parses its contents as a table, and
  then converts that table into a relation. See `clojure.java.io/reader` for a
  complete list of supported arguments."
  [x]
  (let [^Table table (.csv (Table/read) (slurp x) "")
        columns (.columnNames table)
        attrs (map keyword columns)
        row (Row. table)
        coll (loop [i 0
                    rows (transient [])]
               (if (>= i (.rowCount table))
                 (persistent! rows)
                 (do (.at row i)
                     (let [row (zipmap attrs
                                       (map #(.getObject row %)
                                            columns))]
                       (recur (inc i) (conj! rows row))))))]
    (with-meta coll {:iql/columns attrs})))

(defn print-exception
  [e]
  (binding [*out* *err*
            *print-length* 10
            *print-level* 4]
    (if-let [parse-failure (:instaparse/failure (ex-data e))]
      (clojure/print parse-failure)
      (if-let [ex-message (ex-message e)]
        (clojure/println ex-message)
        (repl/pst e)))))

(defn print-table
  "Prints the results of an InferenceQL query to the console as a table."
  [result]
  (if (instance? Exception result)
    (print-exception result)
    (let [columns (:iql/columns (meta result))
          header-row (map name columns)
          cells (for [row result]
                  (reduce-kv (fn [m k v]
                               (assoc m (name k) v))
                             {}
                             row))]
      (pprint/print-table header-row cells))))

(defn print-csv
  "Prints the results of an InferenceQL query to the console as a CSV."
  [result]
  (if (instance? Exception result)
    (print-exception result)
    (let [columns (get (meta result)
                       :iql/columns
                       (into #{} (mapcat keys) result))
          header-row (map name columns)
          cells (map (apply juxt columns) result)
          table (into [header-row] cells)]
      (csv/write-csv *out* table))))

(defn eval
  "Evaluate a query and return the results."
  [query tables models]
  (try (query/q query tables models)
       (catch Exception e
         e)))

(defn repl
  "Launches an interactive InferenceQL REPL (read-eval-print loop)."
  [tables models & {:keys [print] :or {print print-table}}]
  (let [repl-options [:prompt #(clojure.core/print "iql> ")
                      :read (fn [request-prompt request-exit]
                              (case (main/skip-whitespace *in*)
                                :line-start request-prompt
                                :stream-end request-exit
                                (read-line)))
                      :eval #(eval % tables models)
                      :print print]]
    (apply main/repl repl-options)))

(defn errorln
  "Like `clojure.core/println`, but prints to `clojure.core/*err*` instead of
  `clojure.core/*out*`."
  [& args]
  (binding [*out* *err*]
    (apply println args)))

(defn -main
  "Main function for the InferenceQL command-line application. Intended to be run
  with clj -m. Run with -h or --help for more information."
  [& args]
  (let [{:keys [options errors summary]} (cli/parse-opts args cli-options)
        {models :model, query :eval, tables :table, :keys [help output]} options
        print (case output
                "table" print-table
                "csv" print-csv
                nil print-table)]
    (cond (seq errors)
          (doseq [error errors]
            (errorln error))

          (or help
              (and (empty? tables) ; reading from stdin
                   (nil? query)))
          (errorln summary)

          :else
          (let [models (->> (into {}
                                  (map parse-named-pair)
                                  models)
                            (medley/map-keys keyword)
                            (medley/map-vals slurp-model))
                tables (if-not (seq tables)
                         {:data (slurp-csv *in*)}
                         (->> (into {}
                                    (map parse-named-pair)
                                    tables)
                              (medley/map-keys keyword)
                              (medley/map-vals slurp-csv)))]
            (if query
              (print (eval query tables models))
              (repl tables models :print print))))))
