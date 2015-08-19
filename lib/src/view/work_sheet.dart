part of dartsheet.view;

class WorkSheet extends Group {
  
  @event Stream<FrameworkEvent<Cell>> onSelectedCellChanged;
  
  //---------------------------------
  //
  // Protected properties
  //
  //---------------------------------
  
  final StreamController<int> _rowOffsetStreamController = new StreamController();
  final int initRows;
  final int initCols;
  
  //---------------------------------
  //
  // Public properties
  //
  //---------------------------------
  
  Spreadsheet spreadSheet;
  
  //---------------------------------
  // selectedCell
  //---------------------------------
  
  Cell _selectedCell;
  
  Cell get selectedCell => _selectedCell;
  void set selectedCell(Cell value) {
    if (value != _selectedCell) {
      _selectedCell = value;
      
      notify(new FrameworkEvent<Cell>('selectedCellChanged', relatedObject: value));
    }
  }
  
  //---------------------------------
  //
  // Constructor
  //
  //---------------------------------
  
  WorkSheet(this.initRows, this.initCols) : super();
  
  //---------------------------------
  //
  // Public methods
  //
  //---------------------------------
  
  @override
  void createChildren() {
    final ObservableList<Row<Cell<dynamic>>> dataProvider = _createNewDataProvider(0);
    
    super.createChildren();
    
    final HGroup gridGroup = new HGroup(gap: 0)
      ..className = 'workbook'
      ..percentWidth = 100.0
      ..percentHeight = 100.0;
    
    final VGroup columnListGroup = new VGroup(gap: 0)
      ..width = 30
      ..percentHeight = 100.0;
    
    final Spacer spacer = new Spacer()
      ..percentWidth = 100.0
      ..height = 23;
    
    final ListRenderer columnList = new ListRenderer()
      ..percentWidth = 100.0
      ..percentHeight = 100.0
      ..rowHeight = 23
      ..dataProvider = dataProvider
      ..itemRendererFactory = new ItemRendererFactory<RowItemRenderer>(constructorMethod: RowItemRenderer.construct, className: 'row-item-renderer', constructorArguments: <Stream<int>>[_rowOffsetStreamController.stream.asBroadcastStream()])
      ..autoManageScrollBars = false
      ..horizontalScrollPolicy = ScrollPolicy.NONE
      ..verticalScrollPolicy = ScrollPolicy.NONE;
    
    columnListGroup.addComponent(spacer);
    columnListGroup.addComponent(columnList);
    
    spreadSheet = new Spreadsheet()
      ..cssClasses = const <String>[]
      ..percentWidth = 100.0
      ..percentHeight = 100.0
      ..allowHeaderColumnSorting = true
      ..allowMultipleSelection = true
      ..headerHeight = 24
      ..rowHeight = columnList.rowHeight
      ..columnSpacing = 0
      ..rowSpacing = 0
      ..autoScrollOnDataChange = true
      ..dataProvider = dataProvider
      ..columns = _createGridColumns()
      ..useEvenOdd = false
      ..onListScrollPositionChanged.listen(_updateRowIndices)
      ..onHeightChanged.listen(_updateRowIndices)
      ..onRendererAdded.listen(_handleNewRowRenderer);
    
    gridGroup.addComponent(columnListGroup);
    gridGroup.addComponent(spreadSheet);
    
    addComponent(gridGroup);
  }
  
  //---------------------------------
  //
  // Protected methods
  //
  //---------------------------------
  
  ObservableList<Row<Cell<dynamic>>> _createNewDataProvider(int startRowIndex) =>
    new ObservableList<Row<Cell<dynamic>>>.from(
        new List<Row<Cell<dynamic>>>.generate(initRows, (int rowIndex) => _createRow(startRowIndex + rowIndex))
    );
  
  ObservableList<DataGridColumn> _createGridColumns() {
    final ObservableList<DataGridColumn> list = new ObservableList<DataGridColumn>.from(
      new List<DataGridColumn>.generate(initCols, (int i) {
        String id;
        
        if (i >= 26 ) id = new String.fromCharCodes(<int>[64 + i ~/ 26, 65 + i - 26 * (i ~/ 26)]);
        else id = new String.fromCharCode(65 + i);
        
        final Symbol S = new Symbol(id);
      
        return new DataGridColumn()
          ..field = S
          ..width = 120
          ..minWidth = 20
          ..headerData = new HeaderData('', S, id, '')
          ..headerItemRendererFactory = new ItemRendererFactory<HeaderItemRenderer>(constructorMethod: HeaderItemRenderer.construct)
          ..columnItemRendererFactory = new ItemRendererFactory<CellItemRenderer<Cell<String>>>(constructorMethod: CellItemRenderer.construct);
      })
    );
    
    return list;
  }
  
  Row<Cell<dynamic>> _createRow(int rowIndex) {
    final Row<Cell<dynamic>> row = new Row<Cell<dynamic>>(rowIndex);
    
    for (int i=0; i<initCols; i++) row.add(_createCell(toCellIdentity(rowIndex, i), rowIndex, i));
    
    return row;
  }
  
  Cell<dynamic> _createCell(String id, int rowIndex, int colIndex) => new Cell<dynamic>(id, rowIndex, colIndex, null);
  
  void _updateRowIndices(FrameworkEvent event) {
    _rowOffsetStreamController.add(spreadSheet.scrollPosition ~/ spreadSheet.rowHeight);
    
    if (spreadSheet.scrollPosition > (spreadSheet.rowHeight * spreadSheet.dataProvider.length - spreadSheet.height) * .95) spreadSheet.dataProvider.addAll(_createNewDataProvider(spreadSheet.dataProvider.length));
  }
  
  void _handleNewRowRenderer(FrameworkEvent<DataGridItemRenderer> event) {
    event.relatedObject.onRendererAdded.listen(_handleNewCellRenderer);
  }
  
  void _handleNewCellRenderer(FrameworkEvent<CellItemRenderer> event) {
    event.relatedObject.onClick.listen(_handleCellClick);
  }
  
  void _handleCellClick(FrameworkEvent event) {
    final CellItemRenderer<Cell<String>> renderer = event.currentTarget as CellItemRenderer<Cell<String>>;
    final Cell<String> cell = renderer.data;
        
    if (selectedCell != null) selectedCell.selected = false;
    
    selectedCell = cell;
    
    if (selectedCell != null) selectedCell.selected = true;
  }
}